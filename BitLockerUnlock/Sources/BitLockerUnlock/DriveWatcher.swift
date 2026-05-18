import Foundation
import DiskArbitration
import CoreFoundation

/// Wraps DiskArbitration's C callback API into a Swift Concurrency
/// `AsyncStream<[Drive]>`.
///
/// Behaviour:
///   * On `start()`, immediately performs one `BackendBridge.detect()` so the
///     consumer has an initial snapshot.
///   * Each disk-appeared / disappeared callback fires a debounced (250ms)
///     re-detect. Multiple events inside a debounce window collapse into a
///     single rescan.
///   * The watcher schedules itself on a dedicated background thread that
///     owns the CFRunLoop the DASession is attached to.
///
/// Lifecycle: call `start()` once; call `stop()` to tear down. `deinit` also
/// calls `stop()` defensively.
public final class DriveWatcher: @unchecked Sendable {

    public let bridge: BackendBridge

    /// Subscribe here for `[Drive]` snapshots. Replaces previous stream on
    /// each `start()`.
    public private(set) var drives: AsyncStream<[Drive]>
    private var continuation: AsyncStream<[Drive]>.Continuation

    private var session: DASession?
    private var runLoop: CFRunLoop?
    private var workerThread: Thread?

    /// Debounce token. Each callback bumps this; the in-flight debounce task
    /// only triggers a re-detect if the token matches when it wakes up.
    /// Accessed only on the main thread via `MainActor.run`, so no extra
    /// locking is required.
    private var debounceGeneration: UInt64 = 0
    private var debounceTask: Task<Void, Never>?

    public init(bridge: BackendBridge = .shared) {
        self.bridge = bridge
        var localCont: AsyncStream<[Drive]>.Continuation!
        self.drives = AsyncStream<[Drive]> { c in localCont = c }
        self.continuation = localCont
    }

    deinit {
        stop()
    }

    // MARK: Start / stop ------------------------------------------------------

    /// Begin watching. Idempotent — subsequent calls are no-ops while running.
    public func start() {
        guard workerThread == nil else { return }

        // (Re)build the stream so a stop()/start() cycle gives a clean one.
        self.drives = AsyncStream<[Drive]> { [weak self] cont in
            self?.continuation = cont
        }

        let thread = Thread { [weak self] in
            guard let self = self else { return }
            self.runLoop = CFRunLoopGetCurrent()

            guard let session = DASessionCreate(kCFAllocatorDefault) else {
                return
            }
            self.session = session

            let ctx = Unmanaged.passUnretained(self).toOpaque()

            DARegisterDiskAppearedCallback(
                session,
                nil,
                { _, ctx in
                    guard let ctx = ctx else { return }
                    let me = Unmanaged<DriveWatcher>.fromOpaque(ctx).takeUnretainedValue()
                    me.scheduleDebouncedRescan()
                },
                ctx
            )
            DARegisterDiskDisappearedCallback(
                session,
                nil,
                { _, ctx in
                    guard let ctx = ctx else { return }
                    let me = Unmanaged<DriveWatcher>.fromOpaque(ctx).takeUnretainedValue()
                    me.scheduleDebouncedRescan()
                },
                ctx
            )

            DASessionScheduleWithRunLoop(session, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue)

            // Initial snapshot — don't wait for plug events.
            self.scheduleDebouncedRescan()

            CFRunLoopRun()

            // Cleanup when the run loop exits.
            DASessionUnscheduleFromRunLoop(session, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue)
            self.session = nil
            self.runLoop = nil
        }
        thread.name = "DriveWatcher.DARunLoop"
        thread.qualityOfService = .utility
        self.workerThread = thread
        thread.start()
    }

    public func stop() {
        debounceTask?.cancel()
        debounceTask = nil

        if let runLoop = runLoop {
            CFRunLoopStop(runLoop)
        }
        workerThread = nil
        continuation.finish()
    }

    // MARK: Debounce + rescan -------------------------------------------------

    private func scheduleDebouncedRescan() {
        // Hop to the main actor to mutate the generation counter and the
        // debounce task — keeps access serialised without a lock.
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.debounceGeneration &+= 1
            let myGeneration = self.debounceGeneration
            self.debounceTask?.cancel()
            self.debounceTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let self = self else { return }
                let stillCurrent = await MainActor.run { self.debounceGeneration == myGeneration }
                guard stillCurrent, !Task.isCancelled else { return }
                do {
                    let snapshot = try await self.bridge.detect()
                    self.continuation.yield(snapshot)
                } catch {
                    // Detect failures are not fatal to the watcher — emit an
                    // empty snapshot so the UI can show "no drives" rather
                    // than a stale list.
                    self.continuation.yield([])
                }
            }
        }
    }
}

import Foundation
import SwiftUI

/// Single source of truth for the UI. State is modelled as one enum and one
/// `@Published` property so SwiftUI views only need to switch on `state`.
///
/// Instantiate ONE per app, inject as `@EnvironmentObject`. See
/// `INTERFACES.md` for the wiring pattern Wave 2 should use.
@MainActor
public final class AppState: ObservableObject {

    // MARK: State machine ----------------------------------------------------

    public enum State: Equatable {
        /// No BitLocker drives currently detected.
        case idle

        /// One or more candidate drives are plugged in.
        case detected(drives: [Drive])

        /// User is in the credentials modal for the chosen drive.
        case unlockSheet(drive: Drive)

        /// Privileged decrypt is in flight.
        case decrypting(
            drive: Drive,
            progress: Double,
            etaSec: Int?,
            ratePerSec: Int64
        )

        /// Drive is decrypted and mounted at `mountPath`.
        /// `imagePath` is non-nil for `unlock` (file-backed image) and nil
        /// for `mount` (FUSE-T streaming).
        case mounted(drive: Drive, mountPath: String, imagePath: String?)

        /// Terminal error state. `recoverable == true` means the UI should
        /// offer a "Try Again" button; false means "Dismiss" only.
        case error(code: String, message: String, drive: Drive?, recoverable: Bool)
    }

    @Published public private(set) var state: State = .idle

    /// Latest snapshot from `DriveWatcher`. Kept separately so the UI can
    /// always show the drive list, even while `state` is `.mounted` or
    /// `.error`.
    @Published public private(set) var drives: [Drive] = []

    /// Wave 3: a one-shot user-facing alert (currently used by
    /// `promptForManualDrive`). Views observe this and present an alert when
    /// it is non-nil. UI must call `dismissAlert()` after the user
    /// acknowledges.
    @Published public var alertMessage: String? = nil

    // MARK: Dependencies -----------------------------------------------------

    public let bridge: BackendBridge
    public let watcher: DriveWatcher

    private var watchTask: Task<Void, Never>?
    private var unlockTask: Task<Void, Never>?

    public init(
        bridge: BackendBridge = .shared,
        watcher: DriveWatcher? = nil
    ) {
        self.bridge  = bridge
        self.watcher = watcher ?? DriveWatcher(bridge: bridge)
    }

    deinit {
        watchTask?.cancel()
        unlockTask?.cancel()
    }

    // MARK: Lifecycle --------------------------------------------------------

    /// Start the DiskArbitration watcher and begin updating `drives` /
    /// `state`. Call once from `App.init` or `.onAppear`.
    public func startWatching() {
        guard watchTask == nil else { return }
        watcher.start()
        let stream = watcher.drives
        watchTask = Task { [weak self] in
            for await snapshot in stream {
                self?.applyDriveSnapshot(snapshot)
            }
        }
    }

    public func stopWatching() {
        watcher.stop()
        watchTask?.cancel()
        watchTask = nil
    }

    private func applyDriveSnapshot(_ snapshot: [Drive]) {
        let bitLockerDrives = snapshot.filter { $0.isBitLocker }
        self.drives = bitLockerDrives

        // Only auto-transition between .idle and .detected. Don't clobber
        // .unlockSheet / .decrypting / .mounted / .error — those are user-
        // or task-driven.
        switch state {
        case .idle, .detected:
            state = bitLockerDrives.isEmpty ? .idle : .detected(drives: bitLockerDrives)
        default:
            break
        }
    }

    // MARK: User-facing actions ----------------------------------------------

    /// Show the credentials modal for `drive`. Idempotent.
    public func openUnlockSheet(for drive: Drive) {
        state = .unlockSheet(drive: drive)
    }

    /// Close the modal without unlocking. Returns to `.detected` (or `.idle`).
    public func dismissUnlockSheet() {
        state = drives.isEmpty ? .idle : .detected(drives: drives)
    }

    /// Drive the unlock pipeline. Streams progress into `state`.
    /// Must currently be in `.unlockSheet` — otherwise no-op.
    public func attemptUnlock(method: UnlockMethod) async {
        guard case .unlockSheet(let drive) = state else { return }

        // Move straight to decrypting with indeterminate progress until the
        // first progress event lands.
        state = .decrypting(drive: drive, progress: 0, etaSec: nil, ratePerSec: 0)

        unlockTask?.cancel()
        unlockTask = Task { [weak self] in
            guard let self = self else { return }
            let stream = self.bridge.unlock(device: drive.device, method: method)
            do {
                for try await event in stream {
                    if Task.isCancelled { return }
                    await self.consume(event: event, for: drive)
                }
            } catch {
                await self.failWith(
                    code: "unlock_failed",
                    message: error.localizedDescription,
                    drive: drive,
                    recoverable: true
                )
            }
        }
    }

    /// Abort an in-flight unlock. UI returns to `.detected`.
    /// Note: this cancels the Swift task but does NOT kill the privileged
    /// osascript child — that will run to completion in the background.
    public func cancelUnlock() {
        unlockTask?.cancel()
        unlockTask = nil
        state = drives.isEmpty ? .idle : .detected(drives: drives)
    }

    /// Eject the currently-mounted volume (if in `.mounted` state) and return
    /// to `.detected` / `.idle`.
    ///
    /// F5-03 mitigation: when "autoCleanupOnEject" is enabled (default ON)
    /// the plaintext cached image is deleted immediately after a successful
    /// eject so it doesn't persist on disk indefinitely.
    public func ejectMounted() async {
        guard case .mounted(_, let mountPath, let imagePath) = state else { return }
        do {
            try await bridge.eject(mountPath: mountPath)
            // Auto-cleanup: remove the plaintext image to mitigate physical-
            // access risk (F5-03). Runs only when the preference is enabled.
            if UserDefaults.standard.bool(forKey: "autoCleanupOnEject"),
               let imagePath {
                try? await bridge.cleanup(imagePath: imagePath)
            }
            state = drives.isEmpty ? .idle : .detected(drives: drives)
        } catch {
            await failWith(
                code: "eject_failed",
                message: error.localizedDescription,
                drive: nil,
                recoverable: true
            )
        }
    }

    /// Delete the on-disk decrypted image cache. No-op if `state` isn't
    /// `.mounted` with an `imagePath`.
    public func cleanupCachedImage() async {
        guard case .mounted(_, _, let imagePath) = state, let imagePath else { return }
        do {
            try await bridge.cleanup(imagePath: imagePath)
        } catch {
            await failWith(
                code: "cleanup_failed",
                message: error.localizedDescription,
                drive: nil,
                recoverable: true
            )
        }
    }

    /// Acknowledge `.error` and return to `.detected` / `.idle`.
    public func dismissError() {
        state = drives.isEmpty ? .idle : .detected(drives: drives)
    }

    /// Wave 3 placeholder: trigger the "manual drive picker" flow. Wave 4 will
    /// wire `NSOpenPanel` + a device-node selector here. For now we just
    /// surface an alert through `alertMessage`.
    public func promptForManualDrive() {
        alertMessage = "Manual drive picking is not yet implemented."
    }

    /// Clear `alertMessage` once the user has dismissed the alert.
    public func dismissAlert() {
        alertMessage = nil
    }

    // MARK: Helpers ----------------------------------------------------------

    private func consume(event: UnlockEvent, for drive: Drive) async {
        switch event {
        case .progress(let progress, _, _, let ratePerSec, let etaSec):
            state = .decrypting(
                drive: drive,
                progress: progress,
                etaSec: etaSec,
                ratePerSec: ratePerSec
            )
        case .mounted(let mountPath, let imagePath):
            state = .mounted(drive: drive, mountPath: mountPath, imagePath: imagePath)
        case .failed(let code, let message):
            // F6-01 mitigation: never forward raw log-tail content into the
            // UI-visible message. For DECRYPT_FAILED the Python backend embeds
            // up to 20 lines of /tmp/bl/dislocker.log; we replace that with a
            // safe summary and direct the user to the on-disk log for details.
            let safeMessage: String
            if code == "DECRYPT_FAILED" {
                safeMessage = "The decryption tool exited unexpectedly. "
                    + "Details written to /tmp/bl/dislocker.log"
            } else {
                safeMessage = message
            }
            await failWith(
                code: code,
                message: safeMessage,
                drive: drive,
                recoverable: true
            )
        }
    }

    private func failWith(
        code: String,
        message: String,
        drive: Drive?,
        recoverable: Bool
    ) async {
        state = .error(code: code, message: message, drive: drive, recoverable: recoverable)
    }
}

// MARK: - State.caseTag (Wave 3) ------------------------------------------------

public extension AppState.State {
    /// Wave 3: a lightweight discriminator suitable for driving
    /// `.animation(_:value:)`. Avoids the cost of full structural equality
    /// across associated values that change every progress tick (we only
    /// want to animate *case* transitions, not in-state updates).
    var caseTag: String {
        switch self {
        case .idle:        return "idle"
        case .detected:    return "detected"
        case .unlockSheet: return "unlockSheet"
        case .decrypting:  return "decrypting"
        case .mounted:     return "mounted"
        case .error:       return "error"
        }
    }
}

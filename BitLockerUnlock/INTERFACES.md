# BitLockerUnlock — Foundation Layer Quick Reference

Wave 2 agents: this is the **only** file you need to read to wire up UI
screens. Everything below is stable public API for the foundation layer.

---

## 1. How to obtain an `AppState`

`AppState` is created once in `App.swift` as a `@StateObject` and injected
into the SwiftUI environment.

```swift
@main
struct BitLockerUnlockApp: App {
    @StateObject private var appState = AppState()
    var body: some Scene {
        WindowGroup { ContentView().environmentObject(appState) }
    }
}
```

From any descendant view:

```swift
@EnvironmentObject var appState: AppState
```

There is no singleton. Test/preview code may construct an `AppState()`
directly and inject it the same way.

`AppState` is `@MainActor`. All its methods and properties are safe to read
and call from SwiftUI views directly. Background work is internally
hopped off the main actor and back.

---

## 2. `AppState` published surface

### Properties

| Property  | Type        | Notes                                           |
|-----------|-------------|-------------------------------------------------|
| `state`   | `AppState.State` (enum) | The state-machine value. Drives all UI.  |
| `drives`  | `[Drive]`   | Latest snapshot of detected BitLocker drives. |

Both are `@Published` and read-only from outside `AppState`.

### `AppState.State` (enum cases)

```swift
case idle
case detected(drives: [Drive])
case unlockSheet(drive: Drive)
case decrypting(drive: Drive, progress: Double, etaSec: Int?, ratePerSec: Int64)
case mounted(drive: Drive, mountPath: String, imagePath: String?)
case error(code: String, message: String, drive: Drive?, recoverable: Bool)
```

Semantics:

- **idle** — no BitLocker drives plugged in. UI: empty-state.
- **detected** — show the drive list. Tapping a drive should call
  `openUnlockSheet(for:)`.
- **unlockSheet** — show the credentials modal for `drive`.
- **decrypting** — show progress UI. `progress` is in `0...1`. May stay at
  `0` for a while if the CLI hasn't surfaced byte counts yet
  (osascript-blocking limitation; see §5). `etaSec` and a non-zero
  `ratePerSec` will be populated once polling sees the image grow.
- **mounted** — success. Show mount path + buttons for Eject / Cleanup.
- **error** — show error UI. `recoverable == true` ⇒ offer "Try Again";
  otherwise just "Dismiss".

### Methods (all `@MainActor`)

| Signature                                              | When to call                                       |
|--------------------------------------------------------|----------------------------------------------------|
| `func openUnlockSheet(for: Drive)`                     | User taps a drive in the list                      |
| `func dismissUnlockSheet()`                            | User cancels the credentials modal                 |
| `func attemptUnlock(method: UnlockMethod) async`       | User submits the credentials modal                 |
| `func cancelUnlock()`                                  | User taps Cancel during `.decrypting`              |
| `func ejectMounted() async`                            | User taps Eject in `.mounted`                      |
| `func cleanupCachedImage() async`                      | User taps "Delete cached image" in `.mounted`      |
| `func dismissError()`                                  | User taps Dismiss in `.error`                      |
| `func startWatching()` / `func stopWatching()`         | Lifecycle. `App.swift` already calls `startWatching` from `.task` |

---

## 3. Model shapes

### `Drive` (`Models/Drive.swift`)

Matches `bl detect --json` 1:1. `Identifiable` by `device`.

```swift
struct Drive: Codable, Identifiable, Hashable, Sendable {
    let device: String          // e.g. "/dev/disk4s2"
    let name: String            // user-facing label
    let sizeBytes: Int64
    let isBitLocker: Bool
    let isLocked: Bool
    let mountPoint: String      // "" when not mounted
    let filesystem: String
    let bus: String?            // optional; tolerant if absent
    var id: String { device }
}
```

### `UnlockMethod` (`Models/UnlockMethod.swift`)

```swift
enum UnlockMethod: Sendable, Hashable {
    case password(String)
    case recovery(String)
    case bek(URL)
}
```

Exposes `.cliArgs: [String]` for backend wiring (Wave 2 normally won't need
this) and `.label: String` for UI ("Password" / "Recovery Key" / "BEK File").

### `UnlockEvent` (`Models/UnlockEvent.swift`)

Wave 2 normally consumes events indirectly via `AppState.state`. Direct
consumers of `BackendBridge.unlock(...)` see this enum:

```swift
enum UnlockEvent: Sendable, Hashable {
    case progress(progress: Double, bytesDone: Int64, bytesTotal: Int64,
                  ratePerSec: Int64, etaSec: Int?)
    case mounted(mountPath: String, imagePath: String?)
    case failed(code: String, message: String)
}
```

---

## 4. Sizing & style conventions (foundational)

The foundation layer establishes **no colour or sizing tokens** — UI
chrome is Wave 2's responsibility. Two minimal defaults are set by
`App.swift`:

- Main window: `minWidth: 320, minHeight: 200`.
- Menu bar uses SF Symbol `lock.shield`.

Wave 2 should introduce its own design tokens (recommended: a `Theme`
enum in `Chrome/`).

---

## 5. Minimum-viable screen

```swift
struct MinimalDrivesView: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        switch app.state {
        case .idle:                   Text("Plug in a BitLocker drive")
        case .detected(let drives):   List(drives) { d in Button(d.name) { app.openUnlockSheet(for: d) } }
        case .decrypting(_, let p,_,_): ProgressView(value: p)
        default:                      Text(String(describing: app.state))
        }
    }
}
```

---

## 6. Progress events — implementation note for UI authors

Because the privileged `./bl unlock` runs via `osascript ... with
administrator privileges`, the parent process can't read its NDJSON stdout
until the whole operation finishes. The foundation layer works around this
by **polling `/tmp/bl/decrypted.img`'s file size every 500ms** and emitting
synthetic `.progress` events.

Consequences for the UI:

- `progress` may stay at `0.0` for the entire decrypt — `bytesTotal` is
  unknown to the poller. Treat `progress == 0 && ratePerSec > 0` as
  *indeterminate-with-throughput*; render a spinner + "X MB/s" rather than
  a 0% progress bar.
- `etaSec` will likely be `nil` throughout.
- A single `.mounted` (or `.error`) event terminates the stream.

If/when the CLI is reworked to write progress to a tailable side channel
(e.g. `/tmp/bl/progress.ndjson`), only `BackendBridge.unlock(...)` needs to
change — the UI contract is unaffected.

---

## 7. Where the `bl` CLI is located at runtime

`BackendBridge` resolves `bl` in this order:

1. `BL_PATH_OVERRIDE` env var (handy for unit tests / CI).
2. Walks up from `Bundle.main.bundleURL` looking for a sibling executable
   named `bl`. This is the path used for a future bundled `.app`.
3. Falls back to the hard-coded dev path
   `/Users/adamdangerfield/Documents/VS Code Projects/Dislocker/bl`.

Wave 2 doesn't need to do anything; just be aware that integration tests
should set `BL_PATH_OVERRIDE`.

---

## 8. Wave 3 changes (integrator addendum)

Wave 3 wired the eight Wave 2 components together and made the package
build a launchable `.app`. Contract changes future maintainers must know
about:

### New `AppState` surface

| Member                                  | Type              | Purpose                                                                 |
|-----------------------------------------|-------------------|-------------------------------------------------------------------------|
| `alertMessage: String?`                 | `@Published var`  | One-shot user alert. Set by `promptForManualDrive()`; UI shows `.alert` when non-nil. Cleared via `dismissAlert()`. |
| `func promptForManualDrive()`           | `@MainActor`      | Placeholder for Wave 4's `NSOpenPanel`-based manual drive picker. Currently just sets `alertMessage`. Wired to `EmptyView`'s "Pick a drive manually…" link and `DetectedView`'s "Pick a different drive" button. |
| `func dismissAlert()`                   | `@MainActor`      | Clears `alertMessage`. ContentView's alert binding calls this on dismissal. |
| `State.caseTag: String` (extension)     | computed          | Lightweight discriminator (`"idle"`, `"detected"`, … `"error"`) used as the `value:` on `.animation()` so only case transitions animate, not in-state progress updates. |

`alertMessage` is the **only** publicly settable property on `AppState`;
everything else remains `private(set)`. Mutating it directly from a view
is permitted but discouraged outside the alert dismissal path.

### Preview-driven state — decision

We did **not** add a `#if DEBUG _setStateForPreview(_:)` helper. Wave 2
agents already standardised on the "inner content struct" pattern for
the three screens whose state has meaningful associated values
(`DecryptingContent`, `MountedContent`, `ErrorContent`), and the simpler
screens (`EmptyView`, `DetectedView`, `UnlockSheetView`) work fine with
a freshly-constructed `AppState()` in `PreviewProvider`. The content-
struct pattern wins on code-locality (the preview data lives next to the
view that needs it) and avoids leaking a debug-only API onto the public
state type.

If a future screen ever needs to preview a state that can only be
reached via a side-effectful method, copy the `*Content` pattern rather
than reaching for a state-setter on `AppState`.

### App.swift integration

- `ContentView` is now a real router that switches on `app.state` and
  hosts the chrome (preferences popover via a `.toolbar` gear button, a
  `.sheet(isPresented:)` overlay for `UnlockSheetView`, and a `.alert`
  bound to `app.alertMessage`).
- `ContentView` is fixed at `520×640` to match the JSX design envelope;
  combined with `WindowGroup { ... }.windowResizability(.contentSize)`
  this gives the user a non-resizable window of exactly that size.
- Case-transition animations are `.easeInOut(duration: 0.2)` keyed off
  `app.state.caseTag`.
- The `.unlockSheet` case renders `DetectedView` *behind* the sheet so
  the backdrop feels right. `DetectedView` requires `drives: [Drive]`
  at init — the router supplies `app.drives` (or, as a fallback, the
  single sheet drive if `app.drives` is empty, which shouldn't happen
  in practice but guards against a race).

### Release packaging

`make-app.sh` (Wave 3-added) bundles `.build/release/BitLockerUnlock`
into a minimal unsigned `BitLockerUnlock.app`. Run after
`swift build -c release`. Right-click → Open on first launch
(Gatekeeper warning is expected; the app is intentionally unsigned).


import Foundation

/// Mirrors the JSON shape emitted by `./bl detect --json`.
///
/// Example element:
/// ```json
/// {
///   "device":      "/dev/disk4s2",
///   "name":        "MyBitLockerStick",
///   "sizeBytes":   32010928128,
///   "isBitLocker": true,
///   "isLocked":    true,
///   "mountPoint":  "",
///   "filesystem":  "BitLocker",
///   "bus":         "USB"
/// }
/// ```
public struct Drive: Codable, Identifiable, Hashable, Sendable {
    public let device: String          // e.g. "/dev/disk4s2"
    public let name: String            // volume / disk label
    public let sizeBytes: Int64
    public let isBitLocker: Bool
    public let isLocked: Bool
    public let mountPoint: String      // empty string when not mounted
    public let filesystem: String      // e.g. "BitLocker", "ExFAT"
    public let bus: String?            // e.g. "USB", "Thunderbolt"; tolerant if missing

    /// `Identifiable` uses the BSD device node as the stable id.
    public var id: String { device }

    public init(
        device: String,
        name: String,
        sizeBytes: Int64,
        isBitLocker: Bool,
        isLocked: Bool,
        mountPoint: String,
        filesystem: String,
        bus: String? = nil
    ) {
        self.device      = device
        self.name        = name
        self.sizeBytes   = sizeBytes
        self.isBitLocker = isBitLocker
        self.isLocked    = isLocked
        self.mountPoint  = mountPoint
        self.filesystem  = filesystem
        self.bus         = bus
    }
}

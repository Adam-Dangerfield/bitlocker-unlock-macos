import Foundation

/// One item emitted from `BackendBridge.unlock(...)`'s `AsyncThrowingStream`.
///
/// The Python CLI's NDJSON looks like:
///   {"progress":0.42,"bytesDone":12345678,"bytesTotal":29384756,"ratePerSec":987654,"etaSec":17}
/// and finally:
///   {"mountPath":"/Volumes/Foo","imagePath":"/tmp/bl/decrypted.img"}
/// or {"error":"X","message":"..."}
public enum UnlockEvent: Sendable, Hashable {
    case progress(
        progress: Double,
        bytesDone: Int64,
        bytesTotal: Int64,
        ratePerSec: Int64,
        etaSec: Int?
    )
    case mounted(mountPath: String, imagePath: String?)
    case failed(code: String, message: String)
}

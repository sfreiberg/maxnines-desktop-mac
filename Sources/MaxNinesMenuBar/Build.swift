import Foundation

/// Exactly which build this is, as `scripts/bundle.sh` records it in Info.plist,
/// worded as the MaxNines web interface words its own. Run without the bundle,
/// as `swift run` does, none of it is known.
enum Build {
    /// The whole version, such as `0.1.0-alpha.1`, from the VERSION file.
    static var version: String { value("MaxNinesVersion") }
    /// The git commit, ending in `-dirty` if it had uncommitted changes.
    static var commit: String { value("MaxNinesCommit") }
    /// When it was compiled, in UTC.
    static var builtAt: String { value("MaxNinesBuiltAt") }

    static func describe() -> String {
        "MaxNines \(version) · \(commit) · built \(builtAt)"
    }

    private static func value(_ key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "unknown"
    }
}

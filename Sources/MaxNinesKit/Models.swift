import Foundation

/// How bad an alert is, mildest first, so the worse of two is the greater.
public enum Severity: String, Comparable, Sendable {
    case warning
    case critical

    public static func < (left: Severity, right: Severity) -> Bool {
        left == .warning && right == .critical
    }
}

extension Severity: Decodable {
    /// A severity added to the server later is at least a warning.
    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        self = Severity(rawValue: text) ?? .warning
    }
}

/// An alert as the server lists it. Fields this app doesn't use are left out,
/// and the server may add more.
/// Not `Alert`, which SwiftUI has taken.
public struct ServerAlert: Decodable, Identifiable, Equatable, Sendable {
    public let id: Int
    public let ruleId: Int?
    public let ruleName: String
    public let severity: Severity
    public let hostId: String
    public let hostname: String
    public let summary: String
    public let startedMs: Int64
    public let resolvedMs: Int64?
    public let acknowledgedBy: String?
    public let silenceId: Int?
    public let maintenanceWindowId: Int?

    public var isAcknowledged: Bool { acknowledgedBy != nil }
    /// Whether a silence or a maintenance window is keeping its notifications back.
    public var isSilenced: Bool { silenceId != nil || maintenanceWindowId != nil }
}

/// What `GET /api/v1/alerts` returns.
public struct Alerts: Decodable, Equatable, Sendable {
    public let open: [ServerAlert]
    public let resolved: [ServerAlert]

    public init(open: [ServerAlert], resolved: [ServerAlert]) {
        self.open = open
        self.resolved = resolved
    }
}

/// A host the server watches. Not `Host`, which Foundation has taken.
public struct MonitoredHost: Decodable, Identifiable, Equatable, Sendable {
    public let id: String
    public let hostname: String
    public let publicKey: String
    public let state: String
    public let online: Bool

    /// The server lists its own built-in hosts too, which have no agent and no key.
    public var isAgent: Bool { !publicKey.isEmpty && state == "approved" }
}

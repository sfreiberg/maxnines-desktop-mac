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
    /// Which of its rule's series it's about, such as a check's name. Empty for
    /// alerts about the host as a whole, and missing from older servers.
    public let series: String?
    /// What was wrong, as it said when it fired.
    public let summary: String
    public let startedAt: Date
    public let resolvedAt: Date?
    /// Where things stood as it cleared, such as "web-1 is back online". Missing
    /// for one closed for another reason, such as its rule being deleted, and from
    /// older servers.
    public let resolvedSummary: String?
    public let acknowledgedBy: String?
    public let silenceId: Int?
    public let maintenanceWindowId: Int?

    public var isAcknowledged: Bool { acknowledgedBy != nil }
    /// A silence for one alert names its rule, so one whose rule has been deleted
    /// has nothing to name.
    public var canBeSilenced: Bool { ruleId != nil }
    /// Whether a silence or a maintenance window is keeping its notifications back.
    public var isSilenced: Bool { silenceId != nil || maintenanceWindowId != nil }
    /// What it says now: where things stood as it cleared once it has, and what's
    /// wrong until then, as the server's own notifications say.
    public var saysNow: String { resolvedSummary ?? summary }
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

/// A silence: while it runs, the alerts it covers fire and show, but nobody is
/// told about them.
public struct Silence: Decodable, Identifiable, Equatable, Sendable {
    public let id: Int
    /// The alert rule it covers, or every rule.
    public let ruleId: Int?
    /// Which hosts it covers, such as `id=7f3c…` or `hostname=db*`. Empty for all.
    public let filter: String
    /// One series alone, such as a check's name. Empty for all.
    public let series: String
    public let reason: String
    public let endsAt: Date
}

/// What `GET /api/v1/silences` returns. Ones that have ended aren't used.
public struct Silences: Decodable, Equatable, Sendable {
    public let active: [Silence]
}

/// A check the server runs itself, as `GET /api/v1/remote-checks` lists it.
public struct RemoteCheck: Decodable, Identifiable, Equatable, Sendable {
    /// How it last went.
    public struct Latest: Decodable, Equatable, Sendable {
        public let up: Bool
    }

    public let id: Int
    public let enabled: Bool
    /// Missing until it's run since the server started, and from servers too old
    /// to say.
    public let latest: Latest?
}

/// A host the server watches. Not `Host`, which Foundation has taken.
public struct MonitoredHost: Decodable, Identifiable, Equatable, Sendable {
    public let id: String
    public let hostname: String
    public let publicKey: String
    public let state: String
    public let online: Bool
    /// `agent`, `agentless` or `built_in`. A server from before hosts could go
    /// without an agent doesn't say.
    public let kind: String?
    /// How it is, such as `online`, `offline` or `not_read`.
    public let health: String?

    /// Whether it's a host that could be online: approved, not one of the server's
    /// own built-in hosts, and not one with no agent that nothing is read for,
    /// which is neither online nor offline.
    public var isCounted: Bool {
        guard state == "approved", health != "not_read" else { return false }
        // Without a kind, only a built-in host has no key.
        return kind.map { $0 != "built_in" } ?? !publicKey.isEmpty
    }
}

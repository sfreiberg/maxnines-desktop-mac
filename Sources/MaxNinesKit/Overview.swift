import Foundation

/// What the menu bar shows, worked out from what the server lists.
public struct Overview: Equatable, Sendable {
    /// Firing now, worst first and then newest first.
    public let firing: [ServerAlert]
    /// What ended in the last hour, newest first.
    public let resolved: [ServerAlert]
    public let hostsOnline: Int
    public let hosts: Int
    /// The server's own checks, unless it has none or couldn't say.
    public let checks: CheckCount?
    /// Silences running now, ending soonest first.
    public let silences: [SilenceRow]

    static let recently: TimeInterval = 3600
    /// More than this many resolved alerts is a list nobody reads.
    static let mostResolved = 5

    public init(
        alerts: Alerts, hosts: [MonitoredHost], checks: [RemoteCheck]? = nil,
        silences: [Silence] = [], now: Date = Date()
    ) {
        firing = alerts.open.sorted { left, right in
            left.severity != right.severity
                ? left.severity > right.severity : left.startedAt > right.startedAt
        }
        let since = now.addingTimeInterval(-Overview.recently)
        resolved = Array(
            alerts.resolved
                .filter { ($0.resolvedAt ?? .distantPast) >= since }
                .sorted { ($0.resolvedAt ?? .distantPast) > ($1.resolvedAt ?? .distantPast) }
                .prefix(Overview.mostResolved))
        let counted = hosts.filter(\.isCounted)
        self.hosts = counted.count
        hostsOnline = counted.filter(\.online).count
        self.checks = checks.flatMap(CheckCount.init)
        // Alerts are the only place this app learns a rule's name.
        var rules: [Int: String] = [:]
        for alert in alerts.open + alerts.resolved {
            if let rule = alert.ruleId {
                rules[rule] = alert.ruleName
            }
        }
        self.silences = silences
            .sorted { $0.endsAt < $1.endsAt }
            .map { SilenceRow($0, rules: rules, hosts: hosts) }
    }

    public var critical: Int { firing.filter { $0.severity == .critical }.count }
    public var warnings: Int { firing.filter { $0.severity == .warning }.count }

    /// The worst thing firing, which is what the icon says.
    public var worst: Severity? { firing.map(\.severity).max() }

    /// The whole state in a few words, such as `2 critical, 1 warning`.
    public var headline: String {
        var parts: [String] = []
        if critical > 0 {
            parts.append("\(critical) critical")
        }
        if warnings > 0 {
            parts.append(warnings == 1 ? "1 warning" : "\(warnings) warnings")
        }
        return parts.isEmpty ? "Nothing firing" : parts.joined(separator: ", ")
    }
}

/// How the server's own checks are doing. Paused ones aren't counted.
public struct CheckCount: Equatable, Sendable {
    public let passing: Int
    /// The ones that have run since the server started, which is all that can
    /// be passing or not.
    public let run: Int
    public let enabled: Int

    /// Nothing, when there are no checks to count.
    init?(_ checks: [RemoteCheck]) {
        let enabled = checks.filter(\.enabled)
        guard !enabled.isEmpty else { return nil }
        self.enabled = enabled.count
        run = enabled.filter { $0.latest != nil }.count
        passing = enabled.filter { $0.latest?.up == true }.count
    }

    public var failing: Int { run - passing }
}

/// A silence as the menu bar lists it.
public struct SilenceRow: Equatable, Identifiable, Sendable {
    public let id: Int
    public let reason: String
    /// What it keeps quiet, such as `High CPU on web-1`.
    public let covers: String
    public let endsAt: Date

    init(_ silence: Silence, rules: [Int: String], hosts: [MonitoredHost]) {
        id = silence.id
        reason = silence.reason
        endsAt = silence.endsAt
        var what: [String] = []
        if let rule = silence.ruleId {
            what.append(rules[rule] ?? "One alert rule")
        }
        if let series = silence.series {
            what.append(series)
        }
        let filter = silence.filter
        let host = filter.flatMap { filter in hosts.first { "id=\($0.id)" == filter } }
        let where_ = filter.map { host?.hostname ?? $0 } ?? "every host"
        covers = what.isEmpty
            ? (filter == nil ? "Every alert" : "Everything on \(where_)")
            : "\(what.joined(separator: " ")) on \(where_)"
    }
}

/// How long ago something was, in the largest whole unit, such as `4m` or `2h`.
public func age(since then: Date, now: Date = Date()) -> String {
    span(seconds: Int64(now.timeIntervalSince(then)))
}

/// How long until something happens, in the same units as `age`. Part of a
/// second counts as a whole one, so what hasn't happened yet never says `0s`.
public func timeLeft(until then: Date, now: Date = Date()) -> String {
    span(seconds: Int64(then.timeIntervalSince(now).rounded(.up)))
}

func span(seconds: Int64) -> String {
    let seconds = max(0, seconds)
    switch seconds {
    case ..<60: return "\(seconds)s"
    case ..<3600: return "\(seconds / 60)m"
    case ..<86_400: return "\(seconds / 3600)h"
    default: return "\(seconds / 86_400)d"
    }
}

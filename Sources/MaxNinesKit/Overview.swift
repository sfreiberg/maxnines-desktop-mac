import Foundation

/// What the menu bar shows, worked out from what the server lists.
public struct Overview: Equatable, Sendable {
    /// Firing now, worst first and then newest first.
    public let firing: [ServerAlert]
    /// What ended in the last hour, newest first.
    public let resolved: [ServerAlert]
    public let hostsOnline: Int
    public let hosts: Int

    static let recently: Int64 = 3_600_000
    /// More than this many resolved alerts is a list nobody reads.
    static let mostResolved = 5

    public init(alerts: Alerts, hosts: [MonitoredHost], now: Date = Date()) {
        firing = alerts.open.sorted { left, right in
            left.severity != right.severity
                ? left.severity > right.severity : left.startedMs > right.startedMs
        }
        let since = now.milliseconds - Overview.recently
        resolved = Array(
            alerts.resolved
                .filter { ($0.resolvedMs ?? 0) >= since }
                .sorted { ($0.resolvedMs ?? 0) > ($1.resolvedMs ?? 0) }
                .prefix(Overview.mostResolved))
        let counted = hosts.filter(\.isCounted)
        self.hosts = counted.count
        hostsOnline = counted.filter(\.online).count
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

public extension Date {
    var milliseconds: Int64 { Int64((timeIntervalSince1970 * 1000).rounded()) }
}

/// How long ago something was, in the largest whole unit, such as `4m` or `2h`.
public func age(sinceMs then: Int64, now: Date = Date()) -> String {
    let seconds = max(0, (now.milliseconds - then) / 1000)
    switch seconds {
    case ..<60: return "\(seconds)s"
    case ..<3600: return "\(seconds / 60)m"
    case ..<86_400: return "\(seconds / 3600)h"
    default: return "\(seconds / 86_400)d"
    }
}

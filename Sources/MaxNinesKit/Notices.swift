import Foundation

/// Which changes someone wants a notification about.
public struct NotifyWhen: Equatable, Sendable {
    public var critical: Bool
    public var warnings: Bool
    public var resolved: Bool

    public init(critical: Bool, warnings: Bool, resolved: Bool) {
        self.critical = critical
        self.warnings = warnings
        self.resolved = resolved
    }

    public var any: Bool { critical || warnings || resolved }
}

/// One notification to show.
public struct Notice: Equatable, Sendable {
    /// Unique to the change, so the same one is never shown twice.
    public let id: String
    public let title: String
    public let body: String
    /// The alert it's about, which can be acknowledged from it, if it's firing
    /// and nobody has yet.
    public let acknowledges: Int?
    /// The page it opens.
    public let path: String
}

/// More than this many at once become one notification, so a storm doesn't
/// bury the screen.
let mostNotices = 3

/// What's worth a notification between what the server listed last time and
/// now. The first time there's no last time, and nothing is: what was already
/// firing when the app started isn't news.
///
/// Silenced alerts stay quiet, as they do everywhere else in MaxNines.
public func notices(from old: Alerts, to new: Alerts, when: NotifyWhen, now: Date = Date()) -> [Notice] {
    let before = Dictionary(old.open.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let still = Set(new.open.map(\.id))

    var started: [Notice] = []
    for alert in new.open where !alert.isSilenced {
        let was = before[alert.id]
        // A new alert, or one that's got worse.
        guard was == nil || (was?.severity == .warning && alert.severity == .critical) else { continue }
        guard alert.severity == .critical ? when.critical : when.warnings else { continue }
        let level = alert.severity == .critical ? "Critical" : "Warning"
        started.append(
            Notice(
                id: "alert-\(alert.id)-\(alert.severity.rawValue)",
                title: "\(was == nil ? level : "Now critical"): \(alert.ruleName)",
                body: alert.summary,
                acknowledges: alert.isAcknowledged ? nil : alert.id,
                path: page(alert)))
    }

    var ended: [Notice] = []
    if when.resolved {
        let resolved = Dictionary(new.resolved.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for alert in old.open where !still.contains(alert.id) && !alert.isSilenced {
            // Only what the server says has resolved: one that's just gone, as
            // when its host was deleted, isn't news worth telling.
            guard let done = resolved[alert.id] else { continue }
            let lasted = age(sinceMs: done.startedMs, now: Date(milliseconds: done.resolvedMs ?? now.milliseconds))
            ended.append(
                Notice(
                    id: "alert-\(alert.id)-resolved",
                    title: "Resolved: \(alert.ruleName)",
                    body: "\(alert.summary)\nLasted \(lasted)",
                    acknowledges: nil,
                    path: page(alert)))
        }
    }

    return gathered(started, "alerts started") + gathered(ended, "alerts resolved")
}

/// Many at once become one, which opens the alerts page.
private func gathered(_ notices: [Notice], _ what: String) -> [Notice] {
    guard notices.count > mostNotices else { return notices }
    let first = notices.prefix(mostNotices).map(\.body).map { $0.components(separatedBy: "\n")[0] }
    let more = notices.count - mostNotices
    return [
        Notice(
            id: notices.map(\.id).joined(separator: ","),
            title: "\(notices.count) \(what)",
            body: (first + ["and \(more) more"]).joined(separator: "\n"),
            acknowledges: nil,
            path: "/alerts")
    ]
}

/// The page an alert opens: its host's.
public func page(_ alert: ServerAlert) -> String {
    "/hosts/\(alert.hostId)"
}

public extension Date {
    init(milliseconds: Int64) {
        self.init(timeIntervalSince1970: Double(milliseconds) / 1000)
    }
}

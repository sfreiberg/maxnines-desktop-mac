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

    /// Whether an alert this bad starting is wanted.
    public func starts(_ severity: Severity) -> Bool {
        severity == .critical ? critical : warnings
    }
}

/// One notification to show.
public struct Notice: Equatable, Sendable {
    /// Unique to the change, so a later one never takes the place of an earlier
    /// one's notification, as a notification given the same ID does.
    public let id: String
    public let title: String
    public let body: String
    /// The alert it's about, which can be acknowledged from it, if it's firing
    /// and nobody has yet.
    public let acknowledges: Int?
    /// The page it opens.
    public let path: String

    public init(id: String, title: String, body: String, acknowledges: Int?, path: String) {
        self.id = id
        self.title = title
        self.body = body
        self.acknowledges = acknowledges
        self.path = path
    }
}

/// More than this many at once become one notification, so a storm doesn't
/// bury the screen.
let mostNotices = 3

/// Works out notifications from each list of alerts the server gives, keeping
/// what that needs from one to the next.
public struct AlertWatch: Sendable {
    /// What the server listed last time. Nothing until the first answer.
    private var last: Alerts?
    /// Open alerts the person has heard of: ones that, at some time they were
    /// listed, weren't silenced and were of a kind they wanted to hear of.
    private var told: Set<Int> = []

    public init() {}

    /// What's worth a notification since the last list. The first time there's
    /// no last list, and nothing is: what was already firing when the app started
    /// isn't news.
    public mutating func notices(for alerts: Alerts, when: NotifyWhen, now: Date = Date()) -> [Notice] {
        defer {
            last = alerts
            let open = Set(alerts.open.map(\.id))
            told = told.intersection(open).union(heardOf(alerts, when: when))
        }
        guard let last else { return [] }
        return MaxNinesKit.notices(from: last, to: alerts, told: told, when: when, now: now)
    }
}

/// What's worth a notification between `old` and `new`, when the person has
/// heard of the alerts in `old` that they could have.
public func notices(from old: Alerts, to new: Alerts, when: NotifyWhen, now: Date = Date()) -> [Notice] {
    notices(from: old, to: new, told: heardOf(old, when: when), when: when, now: now)
}

/// The open alerts in `alerts` the person would have heard of: not silenced, and
/// of a kind they want to hear of starting. Only these are said to have ended, as
/// hearing an alert has resolved means little without having heard it start.
func heardOf(_ alerts: Alerts, when: NotifyWhen) -> Set<Int> {
    Set(alerts.open.filter { !$0.isSilenced && when.starts($0.severity) }.map(\.id))
}

/// What's worth a notification between `old` and `new`. `told` is the open
/// alerts the person has heard of.
///
/// Silenced alerts stay quiet, as they do everywhere else in MaxNines, except
/// that anyone who has heard of an alert hears when it ends, even if it was
/// silenced since, as the server's own notifications do.
public func notices(from old: Alerts, to new: Alerts, told: Set<Int>, when: NotifyWhen, now: Date = Date())
    -> [Notice]
{
    let before = Dictionary(old.open.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let still = Set(new.open.map(\.id))

    // An alert can start, or get worse, more than once: it can be silenced and
    // then not, or go from warning to critical and back again. So when is part of
    // the ID.
    let moment = Int64((now.timeIntervalSince1970 * 1000).rounded())
    var started: [Notice] = []
    var worst = Severity.warning
    for alert in new.open where !alert.isSilenced {
        let was = before[alert.id]
        // A new alert, one whose silence ended while it was still firing, as the
        // server tells people about then, or one that's got worse.
        let unsilenced = was?.isSilenced == true
        let worse = was?.severity == .warning && alert.severity == .critical
        guard was == nil || unsilenced || worse else { continue }
        guard when.starts(alert.severity) else { continue }
        let level = alert.severity == .critical ? "Critical" : "Warning"
        worst = max(worst, alert.severity)
        started.append(
            Notice(
                id: "alert-\(alert.id)-\(alert.severity.rawValue)-\(moment)",
                title: "\(mark(alert.severity)) \(was == nil || unsilenced ? level : "Now critical"): \(alert.ruleName)",
                body: alert.summary,
                acknowledges: alert.isAcknowledged ? nil : alert.id,
                path: page(alert)))
    }

    var ended: [Notice] = []
    if when.resolved {
        let resolved = Dictionary(new.resolved.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for alert in old.open where !still.contains(alert.id) && told.contains(alert.id) {
            // Only what the server says has resolved: one that's just gone, as
            // when its host was deleted, isn't news worth telling.
            guard let done = resolved[alert.id] else { continue }
            let lasted = age(since: done.breachedAt, now: done.resolvedAt ?? now)
            // Where things stand now, so it doesn't read as the problem again. One
            // closed for another reason has only what was wrong, said as past.
            let outcome = done.resolvedSummary ?? "Was: \(done.summary)"
            ended.append(
                Notice(
                    id: "alert-\(alert.id)-resolved",
                    title: "\(resolvedMark) Resolved: \(alert.ruleName)",
                    body: "\(outcome)\nLasted \(lasted)",
                    acknowledges: nil,
                    path: page(alert)))
        }
    }

    return gathered(started, "\(mark(worst)) \(started.count) alerts started")
        + gathered(ended, "\(resolvedMark) \(ended.count) alerts resolved")
}

/// The coloured circles the server's Discord messages use, so how bad it is, or
/// that it's over, shows before a word is read.
func mark(_ severity: Severity) -> String {
    severity == .critical ? "🔴" : "🟡"
}

let resolvedMark = "🟢"

/// Many at once become one, which opens the alerts page.
private func gathered(_ notices: [Notice], _ title: String) -> [Notice] {
    guard notices.count > mostNotices else { return notices }
    let first = notices.prefix(mostNotices).map(\.body).map { $0.components(separatedBy: "\n")[0] }
    let more = notices.count - mostNotices
    return [
        Notice(
            id: notices.map(\.id).joined(separator: ","),
            title: title,
            body: (first + ["and \(more) more"]).joined(separator: "\n"),
            acknowledges: nil,
            path: "/alerts")
    ]
}

/// The page an alert opens: its own on the server, which every alert has, whether
/// it's about one host, a group of them or the server itself.
public func page(_ alert: ServerAlert) -> String {
    "/alerts/\(alert.id)"
}

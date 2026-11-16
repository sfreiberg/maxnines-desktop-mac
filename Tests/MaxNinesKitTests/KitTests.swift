import Foundation
import Testing

@testable import MaxNinesKit

/// As the server's API documentation shows them.
let alertsJSON = """
    {
      "open": [
        {"id": 7, "rule_id": 1, "rule_name": "High CPU", "severity": "warning",
         "host_id": "22ad9264b6eb708ffdbedcd5cc073e5c", "hostname": "web-1", "series": "",
         "value": 97.2, "summary": "High CPU on web-1", "started_ms": 1793940279545,
         "resolved_ms": null, "resolve_reason": null, "acknowledged_by": null,
         "acknowledged_ms": null, "silence_id": null, "maintenance_window_id": null},
        {"id": 9, "rule_id": null, "rule_name": "Service stopped", "severity": "critical",
         "host_id": "fleet", "hostname": "Fleet", "series": "nginx.service", "value": 0,
         "summary": "Service nginx.service on web-1 is failed", "started_ms": 1793940200000,
         "resolved_ms": null, "resolve_reason": null, "acknowledged_by": "sam@example.com",
         "acknowledged_ms": 1793940210000, "silence_id": 3, "maintenance_window_id": null,
         "added_later": {"anything": true}},
        {"id": 10, "rule_id": 4, "rule_name": "New", "severity": "catastrophic",
         "host_id": "a", "hostname": "db-1", "series": "", "value": null,
         "summary": "Something new", "started_ms": 1793940100000, "resolved_ms": null,
         "resolve_reason": null, "acknowledged_by": null, "acknowledged_ms": null,
         "silence_id": null, "maintenance_window_id": null}
      ],
      "resolved": [
        {"id": 5, "rule_id": 2, "rule_name": "Container down", "severity": "critical",
         "host_id": "a", "hostname": "db-1", "series": "web", "value": 0,
         "summary": "Container web on db-1 is exited", "started_ms": 1793936000000,
         "resolved_ms": 1793939000000, "resolve_reason": "The problem cleared",
         "acknowledged_by": null, "acknowledged_ms": null, "silence_id": null,
         "maintenance_window_id": null},
        {"id": 2, "rule_id": 2, "rule_name": "Container down", "severity": "critical",
         "host_id": "a", "hostname": "db-1", "series": "web", "value": 0,
         "summary": "Long ago", "started_ms": 1793000000000, "resolved_ms": 1793000100000,
         "resolve_reason": "The problem cleared", "acknowledged_by": null,
         "acknowledged_ms": null, "silence_id": null, "maintenance_window_id": null}
      ]
    }
    """

let hostsJSON = """
    [
      {"id": "22ad", "public_key": "912e", "hostname": "web-1", "state": "approved",
       "decided_by": "you@example.com", "first_seen_ms": 1, "decided_ms": 2, "online": true,
       "health": "online", "last_seen_ms": 3},
      {"id": "33be", "public_key": "a1b2", "hostname": "db-1", "state": "approved",
       "online": false, "health": "offline"},
      {"id": "44cf", "public_key": "c3d4", "hostname": "new", "state": "pending", "online": false},
      {"id": "server", "public_key": "", "hostname": "MaxNines server", "state": "approved",
       "online": false},
      {"id": "fleet", "public_key": "", "hostname": "Fleet", "state": "approved", "online": false},
      {"id": "55d0", "kind": "agentless", "public_key": "", "hostname": "orders-db",
       "state": "approved", "online": true, "health": "online", "last_seen_ms": 3},
      {"id": "66e1", "kind": "agentless", "public_key": "", "hostname": "not-set-up-yet",
       "state": "approved", "online": false, "health": "not_read", "last_seen_ms": null},
      {"id": "77f2", "kind": "built_in", "public_key": "", "hostname": "MaxNines server",
       "state": "approved", "online": false, "health": "offline"}
    ]
    """

func decoded() throws -> (Alerts, [MonitoredHost]) {
    let alerts = try Client.decoder.decode(Alerts.self, from: Data(alertsJSON.utf8))
    let hosts = try Client.decoder.decode([MonitoredHost].self, from: Data(hostsJSON.utf8))
    return (alerts, hosts)
}

/// Just after the alerts above.
let now = Date(timeIntervalSince1970: 1_793_940_300)

@Test func alertsAreReadAsTheServerSendsThem() throws {
    let (alerts, _) = try decoded()
    let first = alerts.open[0]
    #expect(first.id == 7)
    #expect(first.ruleId == 1)
    #expect(first.severity == .warning)
    #expect(first.hostname == "web-1")
    #expect(!first.isAcknowledged && !first.isSilenced)

    let second = alerts.open[1]
    #expect(second.ruleId == nil)
    #expect(second.severity == .critical)
    #expect(second.isAcknowledged && second.isSilenced)
    // A severity this app has never heard of still shows.
    #expect(alerts.open[2].severity == .warning)
}

@Test func theOverviewPutsTheWorstFirstAndCountsRealHosts() throws {
    let (alerts, hosts) = try decoded()
    let overview = Overview(alerts: alerts, hosts: hosts, now: now)

    #expect(overview.firing.map(\.id) == [9, 7, 10])
    #expect(overview.worst == .critical)
    #expect(overview.headline == "1 critical, 2 warnings")
    // Only what ended in the last hour.
    #expect(overview.resolved.map(\.id) == [5])
    // Approved hosts, with an agent or without, but not ones waiting, the server's
    // built-in hosts, or one with nothing read for it, which couldn't be online.
    #expect(overview.hosts == 3)
    #expect(overview.hostsOnline == 2)
}

@Test func nothingFiringSaysSo() {
    let overview = Overview(alerts: Alerts(open: [], resolved: []), hosts: [], now: now)
    #expect(overview.headline == "Nothing firing")
    #expect(overview.worst == nil)
}

@Test func agesUseTheLargestWholeUnit() {
    let ago = { (seconds: Int64) in age(sinceMs: now.milliseconds - seconds * 1000, now: now) }
    #expect(ago(0) == "0s")
    #expect(ago(59) == "59s")
    #expect(ago(60) == "1m")
    #expect(ago(3599) == "59m")
    #expect(ago(7200) == "2h")
    #expect(ago(200_000) == "2d")
    // A clock that's a little out doesn't make an age negative.
    #expect(ago(-5) == "0s")
}

@Test func theServerIsFoundFromWhateverPageWasPasted() throws {
    let client = try Client(address: " http://192.168.0.155:9000/alerts?x=1#top ", apiKey: " key\n")
    #expect(client.server.absoluteString == "http://192.168.0.155:9000")
    #expect(client.page("/hosts").absoluteString == "http://192.168.0.155:9000/hosts")
    #expect(client.sendsKeyInTheClear)

    let request = client.request("POST", "alerts/7/acknowledge")
    #expect(request.url?.absoluteString == "http://192.168.0.155:9000/api/v1/alerts/7/acknowledge")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer key")

    #expect(try !Client(address: "https://monitor.example.com", apiKey: "k").sendsKeyInTheClear)
    #expect(try !Client(address: "http://localhost:9000", apiKey: "k").sendsKeyInTheClear)
    for bad in ["", "monitor.example.com", "ftp://example.com", "http://"] {
        #expect(throws: ClientError.badAddress) { try Client(address: bad, apiKey: "k") }
    }
}

@Test func aSilenceCoversTheAlertsRuleOnItsHost() throws {
    let (alerts, _) = try decoded()
    let body = { (alert: ServerAlert) in
        String(decoding: Client.silenceBody(alert, for: 3600), as: UTF8.self)
    }
    #expect(
        body(alerts.open[0])
            == #"{"duration_secs":3600,"filter":"id=22ad9264b6eb708ffdbedcd5cc073e5c","reason":"Silenced from the menu bar","rule_id":1}"#
    )
    // One about a group of hosts has no host to name, and this one's rule is gone.
    #expect(body(alerts.open[1]) == #"{"duration_secs":3600,"reason":"Silenced from the menu bar"}"#)
}

// MARK: Checks and silences

let checksJSON = """
    [
      {"id": 1, "host_id": "server", "check": {"name": "Home page", "kind": "http", "target": "https://example.com"},
       "interval_secs": 60, "enabled": true, "read_stats": false, "sign_in": "none",
       "has_password": false, "has_private_key": false,
       "latest": {"up": true, "ran_ms": 1793940279545}},
      {"id": 2, "host_id": "55d0", "check": {"name": "db", "kind": "postgres", "target": "db:5432"},
       "interval_secs": 60, "enabled": true, "read_stats": true, "extras": ["sizes"], "sign_in": "password",
       "username": "maxnines", "has_password": true, "has_private_key": false,
       "latest": {"up": false, "ran_ms": 1793940279545, "error": "connection refused"}},
      {"id": 3, "host_id": "server", "check": {"name": "New", "kind": "tcp", "target": "a:1"},
       "interval_secs": 60, "enabled": true, "read_stats": false, "sign_in": "none",
       "has_password": false, "has_private_key": false, "latest": null},
      {"id": 4, "host_id": "server", "check": {"name": "Paused", "kind": "tcp", "target": "b:1"},
       "interval_secs": 60, "enabled": false, "read_stats": false, "sign_in": "none",
       "has_password": false, "has_private_key": false, "latest": {"up": false, "ran_ms": 1}}
    ]
    """

let silencesJSON = """
    {
      "active": [
        {"id": 3, "rule_id": null, "filter": "hostname=db*", "series": "", "reason": "Upgrading Postgres",
         "created_by": "you@example.com", "starts_ms": 1793940000000, "ends_ms": 1793947479545},
        {"id": 4, "rule_id": 1, "filter": "id=22ad", "series": "", "reason": "Known",
         "created_by": "you@example.com", "starts_ms": 1793940000000, "ends_ms": 1793941800000},
        {"id": 5, "rule_id": 99, "filter": "", "series": "nginx.service", "reason": "Gone rule",
         "created_by": "you@example.com", "starts_ms": 1793940000000, "ends_ms": 1793950000000},
        {"id": 6, "rule_id": null, "filter": "", "series": "", "reason": "Everything",
         "created_by": "you@example.com", "starts_ms": 1793940000000, "ends_ms": 1793960000000}
      ],
      "ended": [{"id": 1, "rule_id": null, "filter": "", "series": "", "reason": "Old",
                 "created_by": "you@example.com", "starts_ms": 1, "ends_ms": 2}]
    }
    """

@Test func checksCountOnlyWhatsRunningAndHasRun() throws {
    let (alerts, hosts) = try decoded()
    let checks = try Client.decoder.decode([RemoteCheck].self, from: Data(checksJSON.utf8))
    let overview = Overview(alerts: alerts, hosts: hosts, checks: checks, now: now)
    // The paused one isn't counted, and the one that hasn't run can't pass or fail.
    let counted = try #require(overview.checks)
    #expect((counted.passing, counted.run, counted.enabled, counted.failing) == (1, 2, 3, 1))

    // A server with none, or one that couldn't say, has nothing to show.
    #expect(Overview(alerts: alerts, hosts: hosts, checks: [], now: now).checks == nil)
    #expect(Overview(alerts: alerts, hosts: hosts, checks: nil, now: now).checks == nil)
    let paused = checks.filter { !$0.enabled }
    #expect(Overview(alerts: alerts, hosts: hosts, checks: paused, now: now).checks == nil)
}

@Test func checksFromAServerTooOldToSayHaveNotRun() throws {
    let old = """
        [{"id": 1, "host_id": "server", "check": {"name": "a", "kind": "tcp", "target": "a:1"},
          "interval_secs": 60, "enabled": true}]
        """
    let checks = try Client.decoder.decode([RemoteCheck].self, from: Data(old.utf8))
    let (alerts, hosts) = try decoded()
    #expect(Overview(alerts: alerts, hosts: hosts, checks: checks, now: now).checks?.run == 0)
}

@Test func silencesSayWhatTheyCoverAndEndSoonestFirst() throws {
    let (alerts, hosts) = try decoded()
    let silences = try Client.decoder.decode(Silences.self, from: Data(silencesJSON.utf8)).active
    let overview = Overview(alerts: alerts, hosts: hosts, silences: silences, now: now)
    #expect(overview.silences.map(\.id) == [4, 3, 5, 6])
    #expect(overview.silences.map(\.covers) == [
        // A rule named by one of its alerts, on a host named by its ID.
        "High CPU on web-1",
        "Everything on hostname=db*",
        // A rule with no alert to name it.
        "One alert rule nginx.service on every host",
        "Every alert",
    ])
    #expect(overview.silences[0].reason == "Known")
}

@Test func timeLeftRoundsUpAndNeverGoesNegative() {
    let left = { (seconds: Int64) in timeLeft(untilMs: now.milliseconds + seconds * 1000, now: now) }
    #expect(left(25 * 60) == "25m")
    #expect(left(90) == "1m")
    #expect(left(3 * 3600) == "3h")
    #expect(left(-10) == "0s")
    #expect(timeLeft(untilMs: now.milliseconds + 1, now: now) == "1s")
}

// MARK: Notifications

func alert(
    _ id: Int, _ severity: Severity, silenced: Bool = false, acknowledged: Bool = false,
    resolvedMs: Int64? = nil
) -> ServerAlert {
    let json = """
        {"id": \(id), "rule_id": 1, "rule_name": "Rule \(id)", "severity": "\(severity.rawValue)",
         "host_id": "h\(id)", "hostname": "host-\(id)", "summary": "Alert \(id)",
         "started_ms": 1793940000000, "resolved_ms": \(resolvedMs.map(String.init) ?? "null"),
         "acknowledged_by": \(acknowledged ? "\"sam@example.com\"" : "null"),
         "silence_id": \(silenced ? "1" : "null"), "maintenance_window_id": null}
        """
    return try! Client.decoder.decode(ServerAlert.self, from: Data(json.utf8))
}

let everything = NotifyWhen(critical: true, warnings: true, resolved: true)

@Test func newAlertsAreNotifiedAsWanted() {
    let old = Alerts(open: [alert(1, .critical)], resolved: [])
    let new = Alerts(
        open: [alert(1, .critical), alert(2, .critical), alert(3, .warning), alert(4, .critical, silenced: true)],
        resolved: [])
    let all = notices(from: old, to: new, when: everything, now: now)
    // Not the one already firing, nor the silenced one.
    #expect(all.map(\.title) == ["Critical: Rule 2", "Warning: Rule 3"])
    #expect(all[0].body == "Alert 2")
    #expect(all[0].acknowledges == 2)
    #expect(all[0].path == "/hosts/h2")

    let criticalOnly = NotifyWhen(critical: true, warnings: false, resolved: false)
    #expect(notices(from: old, to: new, when: criticalOnly, now: now).map(\.title) == ["Critical: Rule 2"])
    #expect(notices(from: old, to: new, when: NotifyWhen(critical: false, warnings: false, resolved: false)).isEmpty)
}

@Test func anAlertThatGetsWorseIsNotified() {
    let old = Alerts(open: [alert(1, .warning)], resolved: [])
    let new = Alerts(open: [alert(1, .critical, acknowledged: true)], resolved: [])
    let all = notices(from: old, to: new, when: everything, now: now)
    #expect(all.map(\.title) == ["Now critical: Rule 1"])
    // Someone's already on it.
    #expect(all[0].acknowledges == nil)
    // Getting better isn't news.
    #expect(notices(from: new, to: old, when: everything, now: now).isEmpty)
}

@Test func resolvedAlertsSayHowLongTheyLasted() {
    let old = Alerts(open: [alert(1, .critical), alert(2, .warning), alert(3, .critical, silenced: true)], resolved: [])
    let new = Alerts(
        open: [],
        resolved: [alert(1, .critical, resolvedMs: 1793940180000), alert(3, .critical, resolvedMs: 1793940180000)])
    let all = notices(from: old, to: new, when: everything, now: now)
    // The second just went, which the server doesn't call resolved, and the
    // third was silenced.
    #expect(all.map(\.title) == ["Resolved: Rule 1"])
    #expect(all[0].body == "Alert 1\nLasted 3m")
    #expect(all[0].acknowledges == nil)
    #expect(notices(from: old, to: new, when: NotifyWhen(critical: true, warnings: true, resolved: false)).isEmpty)
}

@Test func aStormBecomesOneNotification() {
    let old = Alerts(open: [], resolved: [])
    let new = Alerts(open: (1...5).map { alert($0, .critical) }, resolved: [])
    let all = notices(from: old, to: new, when: everything, now: now)
    #expect(all.count == 1)
    #expect(all[0].title == "5 alerts started")
    #expect(all[0].body == "Alert 1\nAlert 2\nAlert 3\nand 2 more")
    #expect(all[0].path == "/alerts")
    #expect(all[0].acknowledges == nil)
    // Three at once are each shown.
    let three = Alerts(open: (1...3).map { alert($0, .critical) }, resolved: [])
    #expect(notices(from: old, to: three, when: everything, now: now).count == 3)
}

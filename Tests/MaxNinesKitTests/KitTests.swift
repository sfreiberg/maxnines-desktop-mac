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

@Test func theServerIsFoundFromWhateverPageWasPasted() async throws {
    let server = try ServerAddress(" http://192.168.0.155:9000/alerts?x=1#top ")
    #expect(server.url.absoluteString == "http://192.168.0.155:9000")
    #expect(server.page("/hosts").absoluteString == "http://192.168.0.155:9000/hosts")
    #expect(server.isInTheClear)

    let client = Client(server: server, tokens: FixedToken("mxa_1"))
    let request = client.request("POST", "alerts/7/acknowledge", token: "mxa_1")
    #expect(request.url?.absoluteString == "http://192.168.0.155:9000/api/v1/alerts/7/acknowledge")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer mxa_1")

    #expect(try !ServerAddress("https://monitor.example.com").isInTheClear)
    #expect(try !ServerAddress("http://localhost:9000").isInTheClear)
    for bad in ["", "monitor.example.com", "ftp://example.com", "http://"] {
        #expect(throws: ClientError.badAddress) { try ServerAddress(bad) }
    }
}

@Test func aSilenceCoversTheAlertAndNothingElse() throws {
    let (alerts, _) = try decoded()
    let body = { (alert: ServerAlert) in
        String(decoding: try Client.silenceBody(alert, for: 3600), as: UTF8.self)
    }
    // Its rule on its host.
    #expect(
        try body(alerts.open[0])
            == #"{"duration_secs":3600,"filter":"id=22ad9264b6eb708ffdbedcd5cc073e5c","reason":"Silenced from the menu bar","rule_id":1}"#
    )
    // Only its own container, not the rule's others on the same host.
    #expect(
        try body(alerts.resolved[0])
            == #"{"duration_secs":3600,"filter":"id=a","reason":"Silenced from the menu bar","rule_id":2,"series":"web"}"#
    )
    // One about a group of hosts has no host to name, and a filter would leave it out.
    let fleet = try Client.decoder.decode(
        ServerAlert.self,
        from: Data(
            #"""
            {"id": 11, "rule_id": 6, "rule_name": "Half the web hosts down", "severity": "critical",
             "host_id": "fleet", "hostname": "Fleet", "series": "", "summary": "Half down",
             "started_ms": 1, "resolved_ms": null, "acknowledged_by": null, "silence_id": null,
             "maintenance_window_id": null}
            """#.utf8))
    #expect(try body(fleet) == #"{"duration_secs":3600,"reason":"Silenced from the menu bar","rule_id":6}"#)
    // Without its rule, which has been deleted, a silence would cover every rule.
    #expect(!alerts.open[1].canBeSilenced)
    #expect(throws: ClientError.cantSilence) { try Client.silenceBody(alerts.open[1], for: 3600) }
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

@Test func anAlertStillFiringWhenItsSilenceEndsIsNotified() {
    let old = Alerts(open: [alert(1, .critical, silenced: true), alert(2, .warning, silenced: true)], resolved: [])
    let new = Alerts(open: [alert(1, .critical), alert(2, .critical)], resolved: [])
    // As the server tells people then, and as what it is now, not how it changed.
    #expect(notices(from: old, to: new, when: everything, now: now).map(\.title) == ["Critical: Rule 1", "Critical: Rule 2"])
    // Still silenced, it stays quiet.
    #expect(notices(from: old, to: old, when: everything, now: now).isEmpty)
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

// MARK: Signing in

/// Always the same access token, for tests that don't refresh.
struct FixedToken: AccessTokens {
    let token: String
    init(_ token: String) { self.token = token }
    func accessToken() async throws -> String { token }
    func accessToken(replacing rejected: String) async throws -> String { token }
}

/// Something that changes while a test runs, from any task.
final class Box<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
    /// Reads and changes it in one go.
    func locked<Answer>(_ change: (inout Value) -> Answer) -> Answer {
        lock.withLock { change(&stored) }
    }
}

/// Holds back whoever waits on it until it's opened.
actor Gate {
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiting.append($0) }
    }
    func open() {
        isOpen = true
        waiting.forEach { $0.resume() }
        waiting = []
    }
}

/// Answers requests as a server would, and remembers them.
final class FakeServer: Sendable {
    let requests = Box<[URLRequest]>([])
    let answer: @Sendable (URLRequest) async throws -> (Int, String)

    init(_ answer: @escaping @Sendable (URLRequest) async throws -> (Int, String)) {
        self.answer = answer
    }

    var transport: Transport {
        { request in
            self.requests.locked { $0.append(request) }
            let (status, body) = try await self.answer(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        }
    }

    /// How many requests went to `path`.
    func count(_ path: String) -> Int {
        requests.value.filter { $0.url?.path == path }.count
    }
}

/// The fields of a form, or of a URL's query.
func fields(_ encoded: String) -> [String: String] {
    var fields: [String: String] = [:]
    for pair in encoded.split(separator: "&") {
        let parts = pair.split(separator: "=", maxSplits: 1).map {
            $0.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? ""
        }
        fields[parts[0]] = parts.count > 1 ? parts[1] : ""
    }
    return fields
}

func form(_ request: URLRequest) -> [String: String] {
    fields(String(decoding: request.httpBody ?? Data(), as: UTF8.self))
}

func tokensJSON(_ access: String, _ refresh: String, expiresIn: Int = 3600, role: String = "responder") -> String {
    """
    {"access_token": "\(access)", "token_type": "Bearer", "expires_in": \(expiresIn),
     "refresh_token": "\(refresh)", "refresh_token_expires_in": 7776000, "role": "\(role)",
     "user": "you@example.com", "sign_in_id": 4}
    """
}

let testServer = try! ServerAddress("https://monitor.example.com")

@Test func theChallengeIsMadeAsRFC7636Says() {
    // RFC 7636's own example.
    let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
    #expect(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")

    let random = PKCE()
    #expect((43...128).contains(random.verifier.count))
    #expect(random.verifier.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-._~".contains($0)) })
    #expect(random.challenge == PKCE.challenge(for: random.verifier))
    #expect(random.challenge.count == 43)
    #expect(PKCE().verifier != random.verifier)
}

@Test func theApprovalPageIsAskedForWithEverythingTheServerNeeds() throws {
    let server = try ServerAddress("https://monitor.example.com/alerts?x=1")
    let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
    let signIn = BrowserSignIn(server: server, port: 53682, device: " Sam's Mac+Pro & co\n", pkce: pkce, state: "af0ifjsldkj")
    let url = signIn.authorizeURL
    #expect(url.absoluteString.hasPrefix("https://monitor.example.com/oauth/authorize?"))
    // A + in the name would otherwise arrive as a space.
    #expect(url.absoluteString.contains("Mac%2BPro"))
    #expect(
        fields(url.query ?? "") == [
            "response_type": "code",
            "client_id": "maxnines-menubar",
            "redirect_uri": "http://127.0.0.1:53682/callback",
            "code_challenge": "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
            "code_challenge_method": "S256",
            "state": "af0ifjsldkj",
            "device": "Sam's Mac+Pro & co",
            "role": "responder",
        ])

    // The server takes up to 100 characters, with no control characters.
    let long = BrowserSignIn(server: server, port: 1, device: String(repeating: "a\u{7}", count: 150), pkce: pkce, state: "s")
    #expect(long.device == String(repeating: "a", count: 100))
}

@Test func theBrowsersAnswerIsReadAndCheckedAgainstTheState() {
    let signIn = BrowserSignIn(server: testServer, port: 1, device: "", pkce: PKCE(), state: "abc")
    #expect(signIn.answer(fromRequestLine: "GET /callback?code=mxc_123&state=abc HTTP/1.1") == .code("mxc_123"))
    #expect(signIn.answer(fromRequestLine: "GET /callback?error=access_denied&state=abc HTTP/1.1") == .denied)
    #expect(
        signIn.answer(fromRequestLine: "GET /callback?error=invalid_request&state=abc HTTP/1.1")
            == .failed("invalid_request"))
    // An answer to some other request, or none at all, isn't this one's.
    #expect(signIn.answer(fromRequestLine: "GET /callback?code=mxc_123&state=other HTTP/1.1") == nil)
    #expect(signIn.answer(fromRequestLine: "GET /callback?code=mxc_123 HTTP/1.1") == nil)
    #expect(signIn.answer(fromRequestLine: "GET /favicon.ico HTTP/1.1") == nil)
    #expect(signIn.answer(fromRequestLine: "POST /callback?code=mxc_123&state=abc HTTP/1.1") == nil)
    #expect(signIn.answer(fromRequestLine: "") == nil)
}

@Test func anApprovalIsSwappedForTokensAsTheServerExpects() async throws {
    let server = FakeServer { _ in (200, tokensJSON("mxa_1", "mxr_1", role: "viewer")) }
    let signIn = BrowserSignIn(server: testServer, port: 53682, device: "Mac", pkce: PKCE(), state: "s")
    let tokens = try await SignInEndpoints(server: testServer, transport: server.transport)
        .tokens(code: "mxc_1", signIn: signIn)
    #expect(tokens == Tokens(accessToken: "mxa_1", expiresIn: 3600, refreshToken: "mxr_1", role: "viewer", user: "you@example.com"))

    let request = try #require(server.requests.value.first)
    #expect(request.url?.absoluteString == "https://monitor.example.com/oauth/token")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
    #expect(
        form(request) == [
            "grant_type": "authorization_code",
            "client_id": "maxnines-menubar",
            "code": "mxc_1",
            "redirect_uri": "http://127.0.0.1:53682/callback",
            "code_verifier": signIn.pkce.verifier,
        ])
}

@Test func theSignInEndpointsSayWhatWentWrong() async throws {
    let said = Box((400, #"{"error": "invalid_grant", "error_description": "That code is wrong"}"#))
    let server = FakeServer { _ in said.value }
    let endpoints = SignInEndpoints(server: testServer, transport: server.transport)
    let signIn = BrowserSignIn(server: testServer, port: 1, device: "", pkce: PKCE(), state: "s")

    // A code that didn't work isn't being signed out: it's said as the server says it.
    await #expect(throws: OAuthError.said("invalid_grant", "That code is wrong")) {
        try await endpoints.tokens(code: "mxc_1", signIn: signIn)
    }
    #expect(OAuthError.said("invalid_grant", "That code is wrong").localizedDescription == "That code is wrong")
    // A refresh token that doesn't work means signing in again.
    await #expect(throws: ClientError.signedOut) { try await endpoints.refresh("mxr_1") }
    #expect(form(server.requests.value[1]) == ["grant_type": "refresh_token", "client_id": "maxnines-menubar", "refresh_token": "mxr_1"])

    said.value = (500, "oops")
    await #expect(throws: ClientError.status(500)) { try await endpoints.refresh("mxr_1") }
    said.value = (200, "<html>")
    await #expect(throws: ClientError.notMaxNines) { try await endpoints.refresh("mxr_1") }

    said.value = (200, "")
    try await endpoints.revoke("mxr_1")
    let revoke = try #require(server.requests.value.last)
    #expect(revoke.url?.path == "/oauth/revoke")
    #expect(form(revoke) == ["client_id": "maxnines-menubar", "token": "mxr_1"])
}

/// A holder for `server`, which keeps what it saves in `saved`. It doesn't try a
/// failed refresh again unless given delays to wait between tries.
func holder(
    _ server: FakeServer, saved: Box<[Tokens?]>, refreshToken: String = "mxr_0", clock: Box<Date>? = nil,
    retryDelays: [TimeInterval] = []
) -> TokenHolder {
    TokenHolder(
        refreshToken: refreshToken, endpoints: SignInEndpoints(server: testServer, transport: server.transport),
        save: { tokens in saved.locked { $0.append(tokens) } }, now: { clock?.value ?? Date() },
        retryDelays: retryDelays)
}

@Test func aRefreshWhoseAnswerIsLostIsAskedForAgainStraightAway() async throws {
    // The server swapped the token, but its answer never arrived, twice.
    let tries = Box(0)
    let server = FakeServer { request in
        #expect(form(request)["refresh_token"] == "mxr_0")
        let count = tries.locked { $0 += 1; return $0 }
        if count < 3 {
            throw URLError(.networkConnectionLost)
        }
        return (200, tokensJSON("mxa_1", "mxr_1"))
    }
    let saved = Box<[Tokens?]>([])
    let tokens = holder(server, saved: saved, retryDelays: [0, 0, 0])
    #expect(try await tokens.accessToken() == "mxa_1")
    #expect(tries.value == 3)
    #expect(saved.value.map { $0?.refreshToken } == ["mxr_1"])

    // Out of tries, it gives up for now and keeps the token for next time.
    let down = FakeServer { _ in throw URLError(.notConnectedToInternet) }
    let kept = Box<[Tokens?]>([])
    let failing = holder(down, saved: kept, retryDelays: [0, 0])
    await #expect(throws: URLError.self) { try await failing.accessToken() }
    #expect(down.count("/oauth/token") == 3)
    #expect(kept.value.isEmpty)
}

@Test func aRefreshIsOnlyTriedAgainWhileTheServerWouldStillTakeIt() async throws {
    // Each try waited long for its answer, so the next would land past the window.
    let clock = Box(Date(timeIntervalSince1970: 1_000_000))
    let slow = FakeServer { _ in
        clock.value += 40
        throw URLError(.timedOut)
    }
    let tokens = holder(slow, saved: Box([]), clock: clock, retryDelays: [0, 0, 0])
    await #expect(throws: URLError.self) { try await tokens.accessToken() }
    // The first at 40s, a second straight after, then 80s: past the window.
    #expect(slow.count("/oauth/token") == 2)
}

@Test func onlyOneRefreshRunsAndEveryoneWaitsForIt() async throws {
    let gate = Gate()
    let refreshes = Box(0)
    let server = FakeServer { request in
        await gate.wait()
        let count = refreshes.locked { $0 += 1; return $0 }
        return (200, tokensJSON("mxa_\(count)", "mxr_\(count)"))
    }
    let saved = Box<[Tokens?]>([])
    let tokens = holder(server, saved: saved)
    let all = Task {
        try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<10 {
                group.addTask { try await tokens.accessToken() }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }
    }
    // Held at the server until the first refresh has started.
    while server.requests.value.isEmpty {
        await Task.yield()
    }
    for _ in 0..<100 {
        await Task.yield()
    }
    await gate.open()
    let got = try await all.value
    #expect(got == Array(repeating: "mxa_1", count: 10))
    #expect(server.count("/oauth/token") == 1)
    #expect(saved.value.map { $0?.refreshToken } == ["mxr_1"])
}

@Test func theAccessTokenIsRefreshedAMinuteBeforeItRunsOut() async throws {
    let refreshes = Box(0)
    let server = FakeServer { request in
        #expect(form(request)["refresh_token"] == "mxr_\(refreshes.value)")
        refreshes.value += 1
        return (200, tokensJSON("mxa_\(refreshes.value)", "mxr_\(refreshes.value)"))
    }
    let clock = Box(Date(timeIntervalSince1970: 1_000_000))
    let saved = Box<[Tokens?]>([])
    let tokens = holder(server, saved: saved, clock: clock)

    // Nothing in memory yet, as only the refresh token is saved.
    #expect(try await tokens.accessToken() == "mxa_1")
    clock.value += 3600 - 61
    #expect(try await tokens.accessToken() == "mxa_1")
    clock.value += 2
    #expect(try await tokens.accessToken() == "mxa_2")
    #expect(refreshes.value == 2)
    // Each new refresh token is kept, and the next refresh uses it.
    #expect(saved.value.map { $0?.refreshToken } == ["mxr_1", "mxr_2"])
}

@Test func justSignedInTheTokensAreUsedUntilTheyRunOut() async throws {
    let server = FakeServer { _ in (200, tokensJSON("mxa_2", "mxr_2")) }
    let clock = Box(Date(timeIntervalSince1970: 1_000_000))
    let tokens = TokenHolder(
        tokens: Tokens(accessToken: "mxa_1", expiresIn: 3600, refreshToken: "mxr_1", role: "responder", user: "a"),
        endpoints: SignInEndpoints(server: testServer, transport: server.transport), save: { _ in },
        now: { clock.value }, retryDelays: [])
    #expect(try await tokens.accessToken() == "mxa_1")
    #expect(server.requests.value.isEmpty)
    clock.value += 3600
    #expect(try await tokens.accessToken() == "mxa_2")
    #expect(form(server.requests.value[0])["refresh_token"] == "mxr_1")
}

@Test func theNewRefreshTokenIsKeptBeforeTheNewAccessTokenIsUsed() async throws {
    let saved = Box<[Tokens?]>([])
    let server = FakeServer { request in
        if request.url?.path == "/oauth/token" {
            return (200, tokensJSON("mxa_new", "mxr_new"))
        }
        // By the time the new access token reaches the server, its refresh token is kept.
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer mxa_new")
        #expect(saved.value.last??.refreshToken == "mxr_new")
        return (200, "[]")
    }
    let client = Client(server: testServer, tokens: holder(server, saved: saved), transport: server.transport)
    #expect(try await client.hosts().isEmpty)
}

@Test func aRefreshTokenThatNoLongerWorksSignsOut() async throws {
    let server = FakeServer { _ in
        (400, #"{"error": "invalid_grant", "error_description": "That refresh token doesn't work any more"}"#)
    }
    let saved = Box<[Tokens?]>([])
    let tokens = holder(server, saved: saved)
    await #expect(throws: ClientError.signedOut) { try await tokens.accessToken() }
    // It's forgotten, and not tried again.
    #expect(saved.value == [nil])
    await #expect(throws: ClientError.signedOut) { try await tokens.accessToken() }
    #expect(server.requests.value.count == 1)
    #expect(ClientError.signedOut.localizedDescription == "Signed out: sign in again")
}

@Test func aRefreshThatCouldntReachTheServerIsTriedAgain() async throws {
    let fails = Box(true)
    let server = FakeServer { _ in
        if fails.value { throw URLError(.notConnectedToInternet) }
        return (200, tokensJSON("mxa_1", "mxr_1"))
    }
    let saved = Box<[Tokens?]>([])
    let tokens = holder(server, saved: saved)
    await #expect(throws: URLError.self) { try await tokens.accessToken() }
    #expect(saved.value.isEmpty)
    fails.value = false
    #expect(try await tokens.accessToken() == "mxa_1")
    // The same refresh token, as it was never swapped.
    #expect(server.requests.value.map { form($0)["refresh_token"] } == ["mxr_0", "mxr_0"])
}

@Test func aTurnedDownRequestIsRefreshedAndTriedOnceMore() async throws {
    // The first five are held until all five have come, so all are turned down.
    let gate = Gate()
    let held = Box(0)
    let server = FakeServer { request in
        if request.url?.path == "/oauth/token" {
            return (200, tokensJSON("mxa_new", "mxr_new"))
        }
        if request.value(forHTTPHeaderField: "Authorization") == "Bearer mxa_new" {
            return (200, "[]")
        }
        let arrived = held.locked { $0 += 1; return $0 }
        if arrived == 5 {
            await gate.open()
        }
        await gate.wait()
        return (401, "")
    }
    let tokens = TokenHolder(
        tokens: Tokens(accessToken: "mxa_old", expiresIn: 3600, refreshToken: "mxr_old", role: "responder", user: "a"),
        endpoints: SignInEndpoints(server: testServer, transport: server.transport), save: { _ in },
        retryDelays: [])
    let client = Client(server: testServer, tokens: tokens, transport: server.transport)
    // Several turned down at once still refresh only once.
    try await withThrowingTaskGroup(of: Void.self) { group in
        for _ in 0..<5 {
            group.addTask {
                let hosts = try await client.hosts()
                #expect(hosts.isEmpty)
            }
        }
        try await group.waitForAll()
    }
    #expect(server.count("/oauth/token") == 1)
    #expect(server.count("/api/v1/hosts") == 10)
    // Once refreshed, the new token is used from the start.
    _ = try await client.hosts()
    #expect(server.count("/api/v1/hosts") == 11)
}

@Test func aRequestTurnedDownTwiceIsntTriedAThirdTime() async throws {
    let server = FakeServer { _ in (401, "") }
    let client = Client(server: testServer, tokens: FixedToken("mxa_1"), transport: server.transport)
    await #expect(throws: ClientError.notSignedIn) { try await client.hosts() }
    #expect(server.requests.value.count == 2)
}

@Test func whatTheServerSaysIsntAllowedIsShown() async throws {
    let said = Box((403, #"{"error": "This needs the responder role, and this app acts as a viewer"}"#))
    let server = FakeServer { _ in said.value }
    let client = Client(server: testServer, tokens: FixedToken("mxa_1"), transport: server.transport)
    await #expect(throws: ClientError.notAllowed("This needs the responder role, and this app acts as a viewer")) {
        try await client.acknowledge(alertID: 7)
    }
    #expect(
        ClientError.notAllowed("This needs the responder role, and this app acts as a viewer").localizedDescription
            == "This needs the responder role, and this app acts as a viewer")
    said.value = (403, "")
    await #expect(throws: ClientError.notAllowed(nil)) { try await client.acknowledge(alertID: 7) }
}

@Test func signingOutRevokesTheNewestTokenAndForgetsIt() async throws {
    let server = FakeServer { request in
        request.url?.path == "/oauth/token" ? (200, tokensJSON("mxa_1", "mxr_1")) : (200, "")
    }
    let saved = Box<[Tokens?]>([])
    let tokens = holder(server, saved: saved)
    _ = try await tokens.accessToken()
    try await tokens.signOut()
    let revoke = try #require(server.requests.value.last)
    #expect(revoke.url?.path == "/oauth/revoke")
    #expect(form(revoke)["token"] == "mxr_1")
    #expect(saved.value.map { $0?.refreshToken } == ["mxr_1", nil])
    await #expect(throws: ClientError.signedOut) { try await tokens.accessToken() }
    #expect(server.count("/oauth/token") == 1)
}

@Test func signingOutWhenTheServerCantBeToldStillForgets() async throws {
    let server = FakeServer { _ in throw URLError(.cannotConnectToHost) }
    let saved = Box<[Tokens?]>([])
    let tokens = holder(server, saved: saved)
    await #expect(throws: URLError.self) { try await tokens.signOut() }
    #expect(saved.value == [nil])
    #expect(form(server.requests.value[0])["token"] == "mxr_0")
}

// MARK: Through the browser

/// Does what the browser does: asks the server's page, and is sent back to the
/// app with `answer`. Gives back what the app showed for an icon it asked for,
/// and the page it showed at the end.
func browser(answering answer: @escaping @Sendable ([String: String]) -> String, asked: Box<[String: String]>)
    -> (@Sendable (URL) async -> Void, Box<Task<(Int, String), Error>?>)
{
    let visit = Box<Task<(Int, String), Error>?>(nil)
    let open: @Sendable (URL) async -> Void = { url in
        let query = fields(url.query ?? "")
        asked.value = query
        visit.value = Task {
            let session = URLSession(configuration: .ephemeral)
            let redirect = try #require(query["redirect_uri"])
            let root = redirect.replacingOccurrences(of: "/callback", with: "")
            let (_, icon) = try await session.data(from: URL(string: "\(root)/favicon.ico")!)
            let (page, _) = try await session.data(from: URL(string: "\(redirect)?\(answer(query))")!)
            return ((icon as? HTTPURLResponse)?.statusCode ?? 0, String(decoding: page, as: UTF8.self))
        }
    }
    return (open, visit)
}

@Test func signingInThroughTheBrowserGetsTokens() async throws {
    let asked = Box<[String: String]>([:])
    let server = FakeServer { request in
        let sent = form(request)
        // The verifier is the one the challenge sent to the browser was made from.
        #expect(PKCE.challenge(for: sent["code_verifier"] ?? "") == asked.value["code_challenge"])
        #expect(sent["redirect_uri"] == asked.value["redirect_uri"])
        #expect(sent["code"] == "mxc_1")
        return (200, tokensJSON("mxa_1", "mxr_1"))
    }
    let (open, visit) = browser(answering: { "code=mxc_1&state=\($0["state"] ?? "")" }, asked: asked)
    let tokens = try await signInThroughBrowser(
        server: testServer, device: "Sam's Mac", open: open, transport: server.transport)
    #expect(tokens.refreshToken == "mxr_1")
    #expect(asked.value["device"] == "Sam's Mac")
    #expect(asked.value["redirect_uri"]?.hasPrefix("http://127.0.0.1:") == true)

    let (icon, page) = try await #require(visit.value).value
    #expect(icon == 404)
    #expect(page.contains("Signed in to MaxNines"))
    #expect(page.contains("You can close this tab."))
}

@Test func choosingDenyInTheBrowserSaysSoThere() async throws {
    let asked = Box<[String: String]>([:])
    let server = FakeServer { _ in (500, "") }
    let (open, visit) = browser(answering: { "error=access_denied&state=\($0["state"] ?? "")" }, asked: asked)
    await #expect(throws: SignInError.denied) {
        try await signInThroughBrowser(server: testServer, device: "Mac", open: open, transport: server.transport)
    }
    let (_, page) = try await #require(visit.value).value
    #expect(page.contains("Not signed in"))
    #expect(page.contains("You chose Deny"))
    #expect(server.requests.value.isEmpty)
}

@Test func signingInGivesUpWhenNothingComesBack() async throws {
    let server = FakeServer { _ in (500, "") }
    await #expect(throws: SignInError.timedOut) {
        try await signInThroughBrowser(
            server: testServer, device: "Mac", open: { _ in }, transport: server.transport, timeout: .milliseconds(100))
    }
}

@Test func signingInCanBeCancelled() async throws {
    let opened = Box(false)
    let server = FakeServer { _ in (500, "") }
    let signingIn = Task {
        try await signInThroughBrowser(
            server: testServer, device: "Mac", open: { _ in opened.value = true }, transport: server.transport)
    }
    while !opened.value {
        await Task.yield()
    }
    signingIn.cancel()
    await #expect(throws: CancellationError.self) { try await signingIn.value }
}

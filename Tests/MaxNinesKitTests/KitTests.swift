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
      {"id": "fleet", "public_key": "", "hostname": "Fleet", "state": "approved", "online": false}
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
    // Approved agents, not ones waiting or the server's built-in hosts.
    #expect(overview.hosts == 2)
    #expect(overview.hostsOnline == 1)
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

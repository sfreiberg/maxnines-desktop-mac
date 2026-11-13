import MaxNinesKit
import SwiftUI

/// What opens under the menu bar icon.
struct PopoverView: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        // Redrawn now and then, so ages and "updated" keep up between checks.
        TimelineView(.periodic(from: .now, by: 5)) { timeline in
            VStack(spacing: 0) {
                header(now: timeline.date)
                Divider().overlay(Theme.border)
                if !store.isSetUp {
                    notSetUp
                } else if let overview = store.overview {
                    counts(overview)
                    Divider().overlay(Theme.border)
                    alerts(overview, now: timeline.date)
                } else {
                    waiting
                }
                if let problem = store.actionProblem {
                    notice(problem)
                }
                Divider().overlay(Theme.border)
                footer
            }
        }
        .frame(width: 400)
        .background(Theme.surface)
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
    }

    private func header(now: Date) -> some View {
        HStack(spacing: 12) {
            Text("9")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.accentText)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accent))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.headline)
                    .font(.system(size: 14, weight: .semibold))
                Text(status(now: now))
                    .font(Theme.detail)
                    .foregroundStyle(store.problem == nil ? Theme.muted : Theme.warn)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.raised))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.borderStrong))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Refresh")
            .disabled(!store.isSetUp)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    /// Where it's looking, and how fresh what it shows is.
    private func status(now: Date) -> String {
        guard store.isSetUp else { return "Add your server in Settings" }
        let server = URL(string: store.address)?.host() ?? store.address
        if let problem = store.problem {
            let since = store.updated.map { ", last heard \(age(sinceMs: $0.milliseconds, now: now)) ago" }
            return "\(problem)\(since ?? "")"
        }
        guard let updated = store.updated else { return server }
        return "\(server) · updated \(age(sinceMs: updated.milliseconds, now: now)) ago"
    }

    private func counts(_ overview: Overview) -> some View {
        HStack(spacing: 0) {
            count("HOSTS ONLINE", "\(overview.hostsOnline)", of: overview.hosts, path: "/hosts")
            Divider().overlay(Theme.border)
            count(
                "FIRING", "\(overview.firing.count)", path: "/alerts",
                colour: overview.worst == nil ? Theme.good : overview.worst == .critical ? Theme.bad : Theme.warn)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func count(
        _ label: String, _ value: String, of whole: Int? = nil, path: String, colour: Color = Theme.text
    ) -> some View {
        Button {
            store.open(path)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(Theme.label).foregroundStyle(Theme.muted)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value).font(.system(size: 18, weight: .semibold)).foregroundStyle(colour)
                    if let whole {
                        Text("of \(whole)").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func alerts(_ overview: Overview, now: Date) -> some View {
        if overview.firing.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.good)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.goodSurface))
                    .accessibilityHidden(true)
                Text("No alerts are firing").font(.system(size: 14, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else {
            section("FIRING NOW")
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(overview.firing) { alert in
                        FiringRow(alert: alert, now: now)
                        Divider().overlay(Theme.border)
                    }
                }
            }
            // A storm of alerts scrolls rather than running off the screen.
            .frame(maxHeight: 360)
            .fixedSize(horizontal: false, vertical: overview.firing.count <= 4)
        }
        if !overview.resolved.isEmpty {
            Divider().overlay(Theme.border)
            section("RESOLVED IN THE LAST HOUR")
            ForEach(overview.resolved) { alert in
                ResolvedRow(alert: alert, now: now)
            }
        }
    }

    private func section(_ title: String) -> some View {
        Text(title)
            .font(Theme.label)
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    private var notSetUp: some View {
        VStack(spacing: 12) {
            Text("Enter your MaxNines server's address and an API key to see its alerts here.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            SettingsLink { Text("Open Settings") }
                .buttonStyle(QuietButtonStyle())
                .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
        }
        .padding(24)
    }

    private var waiting: some View {
        Text(store.problem == nil ? "Asking the server…" : "Nothing to show until the server answers.")
            .font(.system(size: 13))
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity)
            .padding(24)
    }

    private func notice(_ problem: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.warn)
                .accessibilityHidden(true)
            Text(problem).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Dismiss") { store.actionProblem = nil }
                .buttonStyle(QuietButtonStyle(filled: false))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack(spacing: 4) {
            ForEach([("Overview", "/"), ("Alerts", "/alerts"), ("Hosts", "/hosts"), ("Metrics", "/metrics")], id: \.0) {
                title, path in
                Button(title) { store.open(path) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(store.isSetUp ? Theme.accentInk : Theme.muted)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .disabled(!store.isSetUp)
            }
            Spacer(minLength: 0)
            SettingsLink {
                Image(systemName: "gearshape").frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.muted)
            .accessibilityLabel("Settings")
            .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power").frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.muted)
            .accessibilityLabel("Quit MaxNines")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.sunken)
    }
}

/// One alert that's firing, with what can be done about it.
private struct FiringRow: View {
    @EnvironmentObject private var store: Store
    let alert: ServerAlert
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Told apart by shape as well as colour.
            Group {
                if alert.severity == .critical {
                    Circle().fill(Theme.bad)
                } else {
                    RoundedRectangle(cornerRadius: 2).fill(Theme.warn)
                }
            }
            .frame(width: 9, height: 9)
            .padding(.top, 5)
            .accessibilityLabel(alert.severity == .critical ? "Critical" : "Warning")

            VStack(alignment: .leading, spacing: 4) {
                Button {
                    store.open("/hosts/\(alert.hostId)")
                } label: {
                    Text(alert.summary)
                        .font(.system(size: 13, weight: .medium))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.plain)
                Text(detail).font(Theme.detail).foregroundStyle(Theme.muted)
                if !alert.isAcknowledged || !alert.isSilenced {
                    HStack(spacing: 8) {
                        if !alert.isAcknowledged {
                            Button("Acknowledge") { store.acknowledge(alert) }
                                .buttonStyle(QuietButtonStyle())
                        }
                        if !alert.isSilenced {
                            Button("Silence 1 hour") { store.silenceForAnHour(alert) }
                                .buttonStyle(QuietButtonStyle(filled: false))
                        }
                    }
                    .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var detail: String {
        var parts = [alert.ruleName, age(sinceMs: alert.startedMs, now: now)]
        if let who = alert.acknowledgedBy {
            parts.append("acknowledged by \(who)")
        }
        if alert.isSilenced {
            parts.append("silenced")
        }
        return parts.joined(separator: " · ")
    }
}

private struct ResolvedRow: View {
    @EnvironmentObject private var store: Store
    let alert: ServerAlert
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.good)
                .padding(.top, 3)
                .accessibilityLabel("Resolved")
            VStack(alignment: .leading, spacing: 3) {
                Button {
                    store.open("/hosts/\(alert.hostId)")
                } label: {
                    Text(alert.summary)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.plain)
                Text("\(alert.ruleName) · \(age(sinceMs: alert.resolvedMs ?? alert.startedMs, now: now)) ago")
                    .font(Theme.detail)
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

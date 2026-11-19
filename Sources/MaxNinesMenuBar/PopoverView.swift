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
                    SignInPanel()
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
                if let problem = store.saveProblem {
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
        guard store.isSetUp else { return store.problem ?? "Not signed in" }
        let server = URL(string: store.address)?.host() ?? store.address
        if let problem = store.problem {
            let since = store.updated.map { ", last heard \(age(since: $0, now: now)) ago" }
            return "\(problem)\(since ?? "")"
        }
        guard let updated = store.updated else { return server }
        return "\(server) · updated \(age(since: updated, now: now)) ago"
    }

    private func counts(_ overview: Overview) -> some View {
        HStack(spacing: 0) {
            count("HOSTS ONLINE", "\(overview.hostsOnline)", of: overview.hosts, path: "/hosts")
            Divider().overlay(Theme.border)
            count(
                "FIRING", "\(overview.firing.count)", path: "/alerts",
                colour: overview.worst == nil ? Theme.good : overview.worst == .critical ? Theme.bad : Theme.warn)
            if let checks = overview.checks {
                Divider().overlay(Theme.border)
                // Only checks that have run can pass or fail, so until any has
                // since the server started, there's nothing to count.
                if checks.run == 0 {
                    count("CHECKS PASSING", "–", path: "/checks", colour: Theme.muted)
                } else {
                    count(
                        "CHECKS PASSING", "\(checks.passing)", of: checks.run, path: "/checks",
                        colour: checks.failing > 0 ? Theme.bad : Theme.text)
                }
            }
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
        if !overview.silences.isEmpty {
            Divider().overlay(Theme.border)
            section("SILENCED")
            ForEach(overview.silences.prefix(PopoverView.mostSilences)) { silence in
                SilenceRowView(silence: silence, now: now)
            }
            let more = overview.silences.count - PopoverView.mostSilences
            if more > 0 {
                Button("\(more) more") { store.open("/alerts/silences") }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.accentInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }
        }
    }

    /// More silences than this are left to the Silences page.
    static let mostSilences = 3

    private func section(_ title: String) -> some View {
        Text(title)
            .font(Theme.label)
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)
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
                    store.open(page(alert))
                } label: {
                    Text(alert.summary)
                        .font(.system(size: 13, weight: .medium))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.plain)
                Text(detail).font(Theme.detail).foregroundStyle(Theme.muted)
                // A silence names the alert's rule, so one whose rule is gone can't have one.
                let canSilence = !alert.isSilenced && alert.canBeSilenced
                if !alert.isAcknowledged || canSilence {
                    HStack(spacing: 8) {
                        if !alert.isAcknowledged {
                            Button("Acknowledge") { store.acknowledge(alert) }
                                .buttonStyle(QuietButtonStyle())
                        }
                        if canSilence {
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
        var parts = [alert.ruleName, age(since: alert.breachedAt, now: now)]
        if let who = alert.acknowledgedBy {
            parts.append("acknowledged by \(who)")
        }
        if alert.isSilenced {
            parts.append("silenced")
        }
        return parts.joined(separator: " · ")
    }
}

/// A silence that's running: why, what it keeps quiet and when it ends.
private struct SilenceRowView: View {
    @EnvironmentObject private var store: Store
    let silence: SilenceRow
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bell.slash")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .padding(.top, 2)
                .accessibilityLabel("Silenced")
            VStack(alignment: .leading, spacing: 3) {
                Button {
                    store.open("/alerts/silences")
                } label: {
                    Text(silence.reason)
                        .font(.system(size: 13))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.plain)
                Text("\(silence.covers) · ends in \(timeLeft(until: silence.endsAt, now: now))")
                    .font(Theme.detail)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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
                    store.open(page(alert))
                } label: {
                    Text(alert.saysNow)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.plain)
                Text("\(alert.ruleName) · \(age(since: alert.resolvedAt ?? alert.startedAt, now: now)) ago")
                    .font(Theme.detail)
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

/// Signing in, right in the menu: a button that opens the browser, with a place for the
/// server's address the first time, before there's one to sign in to.
private struct SignInPanel: View {
    @EnvironmentObject private var store: Store
    @State private var typed = ""
    /// Signing in to a server other than the one saved.
    @State private var another = false

    var body: some View {
        VStack(spacing: 12) {
            if store.signingIn {
                ProgressView().controlSize(.small)
                Text("Waiting for you to allow it in the browser…")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                Button("Cancel") { store.cancelSignIn() }
                    .buttonStyle(QuietButtonStyle(filled: false))
            } else {
                Text(
                    store.wasSignedOut
                        ? "Signed out. Sign in again to see its alerts here."
                        : "Sign in to your MaxNines server to see its alerts here."
                )
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                if store.address.isEmpty || another {
                    HStack(spacing: 8) {
                        TextField("Server address", text: $typed, prompt: Text("https://monitor.example.com"))
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .onSubmit(signInTyped)
                        Button("Sign in", action: signInTyped)
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if another {
                        Button("Back to \(saved)") { another = false }
                            .buttonStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.accentInk)
                    }
                } else {
                    Button("Sign in to \(saved)") { store.signIn(address: store.address) }
                        .buttonStyle(PrimaryButtonStyle())
                    Button("Use another server") {
                        typed = ""
                        another = true
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.accentInk)
                }
                if let problem = store.signInProblem {
                    Text(problem)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.bad)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    /// The saved server as people know it: its name or address, without the scheme.
    private var saved: String {
        URL(string: store.address)?.host() ?? store.address
    }

    private func signInTyped() {
        let address = typed.trimmingCharacters(in: .whitespaces)
        guard !address.isEmpty else { return }
        another = false
        store.signIn(address: address)
    }
}

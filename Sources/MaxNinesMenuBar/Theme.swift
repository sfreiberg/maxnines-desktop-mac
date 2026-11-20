import SwiftUI

/// The colours of MaxNines' own Carbon theme, so the app looks like the site.
enum Theme {
    static let background = Color(hex: 0x08090B)
    static let surface = Color(hex: 0x0F1114)
    static let sunken = Color(hex: 0x0A0B0E)
    static let raised = Color(hex: 0x1B1E24)
    static let text = Color(hex: 0xF3F5F4)
    static let muted = Color(hex: 0x9EA5AB)
    static let border = Color(hex: 0x1E2227)
    static let borderStrong = Color(hex: 0x30353C)
    static let accent = Color(hex: 0x6FDC8C)
    static let accentText = Color(hex: 0x06200F)
    static let accentInk = Color(hex: 0x8CE8A4)
    static let good = Color(hex: 0x6FDC8C)
    static let goodSurface = Color(hex: 0x102A1A)
    static let bad = Color(hex: 0xFF7B7D)
    static let warn = Color(hex: 0xF0B64E)

    /// Small capitals over a section, as the site labels things.
    static let label = Font.system(size: 10, weight: .medium, design: .monospaced)
    static let detail = Font.system(size: 11, design: .monospaced)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}

/// The quiet bordered button used for what can be done to an alert.
struct QuietButtonStyle: ButtonStyle {
    var filled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(filled || configuration.isPressed ? Theme.raised : .clear)
            )
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.borderStrong))
            .contentShape(RoundedRectangle(cornerRadius: 7))
    }
}

/// The one thing to do next, in the accent colour.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.accentText)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Theme.accent.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4))
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
    }
}

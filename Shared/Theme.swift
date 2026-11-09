import SwiftUI

/// Visual language inspired by the AURA Finance Widgets UI kit: near-black
/// cards lit by a coloured glow from one corner, large medium-weight figures
/// with small dim units, white pill buttons. Dark only.
///
/// Fonts are the system's (SF Pro) rather than the kit's Switzer and Rethink
/// Sans, so everything still follows the user's text size.
enum Theme {
    // Surfaces
    static let page = Color.black
    static let card = Color(red: 0.04, green: 0.04, blue: 0.04)      // #0A0A0A
    static let overlay = Color.white.opacity(0.09)                    // bg/overlay-alpha-primary
    static let hairline = Color.white.opacity(0.07)

    // Text
    static let secondaryText = Color.white.opacity(0.5)
    static let tertiaryText = Color.white.opacity(0.4)

    // Palette (kit primitives)
    static let green = Color(hex: 0x16B364)      // green/500
    static let greenDeep = Color(hex: 0x099250)  // green/600
    static let lime = Color(hex: 0xA3E635)       // lime/400
    static let orange = Color(hex: 0xF97316)
    static let pink = Color(hex: 0xDB2777)       // pink/600
    static let blue = Color(hex: 0x2E90FA)       // blue/500
    static let purple = Color(hex: 0x7A5AF8)
    static let lavender = Color(hex: 0xBDB4FE)   // purple/300

    static let cornerRadius: CGFloat = 24        // 3xl
    static let padding: CGFloat = 16             // base

    // Type: kit sizes mapped to text styles, so they scale with Dynamic Type.
    static let cardTitle = Font.callout.weight(.medium)          // Label-1, 16pt
    static let caption = Font.caption                            // Label-3, 12pt
    static let hero = Font.system(.largeTitle).weight(.medium)   // H3
    static let figure = Font.system(.title2).weight(.medium)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

extension UsageSnapshot.Level {
    /// Short status for the ring's pill.
    var label: String {
        switch self {
        case .ok: return "On track"
        case .warning: return "Nearing budget"
        case .over: return "Over budget"
        }
    }
}

/// A near-black card with a coloured glow coming in from one corner.
struct GlowBackground: View {
    var color: Color
    var from: UnitPoint = .topTrailing
    var radius: CGFloat = 320

    var body: some View {
        ZStack {
            Theme.card
            RadialGradient(colors: [color.opacity(0.75), color.opacity(0.25), .clear],
                           center: from, startRadius: 0, endRadius: radius)
        }
    }
}

extension View {
    /// Wraps content in a glowing AURA-style card.
    func auraCard(glow: Color, from: UnitPoint = .topTrailing) -> some View {
        self
            .padding(Theme.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GlowBackground(color: glow, from: from))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

/// "2.00" large + " GB" small and dim, as one Text so it shrinks as a unit.
func figureText(_ bytes: Int64, font: Font = Theme.hero, unitFont: Font = .subheadline) -> Text {
    let parts = DataFormat.parts(bytes)
    return Text(parts.value).font(font).foregroundColor(.white)
        + Text(" \(parts.unit)").font(unitFont).foregroundColor(Theme.secondaryText)
}


// MARK: - Dashboard style (shared with the widget)

/// Chart colours shared by the dashboard, its insight pages and the widget.
enum Palette {
    static let teal = Color(hex: 0x5ED9C4)
    static let cyan = Color(hex: 0x5CD6E6)
    static let orange = Color(hex: 0xF0A04B)
    static let blue = Color(hex: 0x3D8BFF)
    static let skyBlue = Color(hex: 0x5BC8FA)
    static let magenta = Color(hex: 0xD94FE0)
    static let yellow = Color(hex: 0xF2CF4B)
    static let green = Color(hex: 0x4ADE80)
    static let red = Color(hex: 0xF0525F)
    static let ink = Color(hex: 0x050508)
}

extension UsageSnapshot.Level {
    /// The hero ring's gradient, start to end.
    var ringColors: [Color] {
        switch self {
        case .ok: return [Color(hex: 0x2F6BFF), Palette.skyBlue]
        case .warning: return [Color(hex: 0xF97316), Color(hex: 0xFDBA74)]
        case .over: return [Color(hex: 0xDB2777), Color(hex: 0xF472B6)]
        }
    }

    /// The dashboard's background wash.
    var wash: Color {
        switch self {
        case .ok: return Color(hex: 0x0F2A4D)
        case .warning: return Color(hex: 0x3D2410)
        case .over: return Color(hex: 0x3D0F26)
        }
    }
}

/// A screen background: a colour wash at the top fading into near-black.
struct WashBackground: View {
    let color: Color

    var body: some View {
        ZStack {
            Palette.ink
            LinearGradient(colors: [color, color.opacity(0.35), .clear],
                           startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.6))
        }
    }
}

extension UsageSnapshot {
    /// True once today's usage has passed today's budget.
    var isOverToday: Bool { todayBytes > dailyBudgetBytes }

    /// The lit part of the hero ring: what's left of today's budget, or once
    /// over, how far over (a quarter ring = 25% over).
    var ringFraction: Double { isOverToday ? todayFraction - 1 : 1 - todayFraction }

    /// The ring's centre figure: left today, or over by.
    var ringFigureBytes: Int64 { isOverToday ? todayBytes - dailyBudgetBytes : todayRemainingBytes }
}

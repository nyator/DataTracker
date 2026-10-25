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
    var color: Color {
        switch self {
        case .ok: return Theme.green
        case .warning: return Theme.orange
        case .over: return Theme.pink
        }
    }

    /// Short status for the Today card's pill.
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

/// Small capsule label, e.g. "62 days left".
struct Pill: View {
    let text: String
    var color: Color = .white

    var body: some View {
        Text(text)
            .font(Theme.caption.weight(.medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .overlay(Capsule().strokeBorder(color.opacity(0.6), lineWidth: 1))
    }
}

/// Segmented meter (the kit's "Credit Score" bar): lit segments up to `fraction`.
struct TickMeter: View {
    let fraction: Double
    var color: Color
    var segments = 32
    var height: CGFloat = 28

    var body: some View {
        let lit = Int((min(max(fraction, 0), 1) * Double(segments)).rounded())
        HStack(spacing: 3) {
            ForEach(0..<segments, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(i < lit ? color : Color.white.opacity(0.18))
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("\(Int((fraction * 100).rounded())) percent used")
    }
}

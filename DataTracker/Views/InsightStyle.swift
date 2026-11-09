import SwiftUI

/// Colours for one insight: its card on the dashboard, its accent (charts,
/// status dots), and the wash at the top of its detail page.
struct InsightTint {
    let card: Color
    let accent: Color
    let wash: Color
}

extension Insight {
    var tint: InsightTint {
        switch self {
        case .trend: return InsightTint(card: Color(hex: 0x151A33), accent: Palette.cyan, wash: Color(hex: 0x3A3F8C))
        case .bundle: return InsightTint(card: Color(hex: 0x231029), accent: Palette.teal, wash: Color(hex: 0x6A2280))
        case .calendar: return InsightTint(card: Color(hex: 0x2A1A0D), accent: Palette.orange, wash: Color(hex: 0x4D3420))
        case .pace: return InsightTint(card: Color(hex: 0x0C1F35), accent: Palette.blue, wash: Color(hex: 0x1D4E8F))
        case .plan: return InsightTint(card: Color(hex: 0x0B282C), accent: Palette.teal, wash: Color(hex: 0x1C5A5E))
        case .remaining: return InsightTint(card: Color(hex: 0x0E2516), accent: Palette.green, wash: Color(hex: 0x2B6A30))
        }
    }
}

/// A round, glassy icon button face (close, settings, previous/next).
struct GlassCircle: View {
    let systemImage: String
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: systemImage)
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.white.opacity(0.12)))
            .overlay(Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
            .contentShape(Circle())
    }
}

/// Shrinks a little while pressed, for cards that act as buttons.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// "+1.20" large + " GB" small and dim, with a sign.
func signedFigureText(_ bytes: Int64, font: Font, unitFont: Font = .subheadline) -> Text {
    let parts = DataFormat.parts(abs(bytes))
    let sign = bytes > 0 ? "+" : (bytes < 0 ? "−" : "")
    return Text(sign + parts.value).font(font).foregroundColor(.white)
        + Text(" \(parts.unit)").font(unitFont).foregroundColor(Theme.secondaryText)
}

/// "+23" large + " %" small and dim.
func percentFigureText(_ percent: Int, font: Font, unitFont: Font = .subheadline) -> Text {
    Text(percent > 0 ? "+\(percent)" : (percent < 0 ? "−\(-percent)" : "0")).font(font).foregroundColor(.white)
        + Text(" %").font(unitFont).foregroundColor(Theme.secondaryText)
}

/// "2.1" for gigabytes, "640M" below 1 GB: short enough for a calendar cell or bar label.
func shortAmount(_ bytes: Int64) -> String {
    let gb = Budget.gb(fromBytes: bytes)
    if gb >= 1 { return String(format: "%.1f", gb) }
    return "\(Int((Double(bytes) / 1_048_576).rounded()))M"
}

/// The figure fonts, as text styles so they follow the user's text size.
enum FigureFont {
    static let hero = Font.system(.largeTitle).weight(.bold)
    static let page = Font.system(.largeTitle).weight(.bold)
    static let card = Font.system(.title2).weight(.bold)
    static let stat = Font.system(.title3).weight(.medium)
}

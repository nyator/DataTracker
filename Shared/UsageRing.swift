import SwiftUI

extension UsageSnapshot.Level {
    var color: Color {
        switch self {
        case .ok: return .green
        case .warning: return .orange
        case .over: return .red
        }
    }
}

/// Today's usage against the budget. Past 100%, a thin white lap drawn over
/// the full ring shows how far over (e.g. a quarter lap = 125%).
struct UsageRing<Center: View>: View {
    let fraction: Double
    let color: Color
    var lineWidth: CGFloat = 14
    @ViewBuilder var center: () -> Center

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(fraction, 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if fraction > 1 {
                Circle()
                    .trim(from: 0, to: min(fraction - 1, 1))
                    .stroke(Color.white.opacity(0.75), style: StrokeStyle(lineWidth: lineWidth * 0.35, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            center()
        }
        .padding(lineWidth / 2)
    }
}

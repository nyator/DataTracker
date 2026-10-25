import SwiftUI

/// Today's usage against the budget, in the style of the kit's "Spend this
/// month" ring: a dim track, a stroke that brightens towards its end, and a
/// white knob marking the current point. Past 100%, a thin white lap drawn
/// over the full ring shows how far over (a quarter lap = 125%).
struct UsageRing<Center: View>: View {
    let fraction: Double
    let color: Color
    var lineWidth: CGFloat = 14
    @ViewBuilder var center: () -> Center

    var body: some View {
        let shown = min(max(fraction, 0), 1)
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.14), lineWidth: lineWidth)
            if shown > 0 {
                Circle()
                    .trim(from: 0, to: shown)
                    .stroke(AngularGradient(colors: [color.opacity(0.35), color],
                                            center: .center,
                                            startAngle: .degrees(0),
                                            endAngle: .degrees(360 * shown)),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            if fraction > 1 {
                Circle()
                    .trim(from: 0, to: min(fraction - 1, 1))
                    .stroke(Color.white.opacity(0.75), style: StrokeStyle(lineWidth: lineWidth * 0.35, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            if shown > 0 {
                Knob(angle: .degrees(360 * shown), size: lineWidth * 0.5)
            }
            center()
        }
        .padding(lineWidth / 2)
    }
}

/// White dot sitting on the ring at `angle` (clockwise from 12 o'clock).
private struct Knob: View {
    let angle: Angle
    let size: CGFloat

    var body: some View {
        GeometryReader { g in
            let r = min(g.size.width, g.size.height) / 2
            Circle()
                .fill(.white)
                .frame(width: size, height: size)
                .position(x: g.size.width / 2 + r * sin(angle.radians),
                          y: g.size.height / 2 - r * cos(angle.radians))
        }
    }
}

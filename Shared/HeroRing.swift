import SwiftUI

/// The dashboard's big ring: a thick gradient arc from 12 o'clock, with a
/// ring of dots inside it that light up along the same stretch.
struct HeroRing<Center: View>: View {
    /// 0…1, the lit part of the ring.
    let fraction: Double
    let colors: [Color]
    var lineWidth: CGFloat = 22
    var dotCount = 44
    @ViewBuilder var center: () -> Center

    var body: some View {
        let shown = min(max(fraction, 0), 1)
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.06), lineWidth: lineWidth)
            if shown > 0 {
                Circle()
                    .trim(from: 0, to: shown)
                    .stroke(AngularGradient(colors: colors, center: .center,
                                            startAngle: .degrees(0), endAngle: .degrees(360 * shown)),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: (colors.last ?? .white).opacity(0.35), radius: 12)
            }
            DotRing(fraction: shown, count: dotCount, color: colors.last ?? .white)
                .padding(lineWidth * 1.4)
            center()
        }
        .padding(lineWidth / 2)
        .animation(.easeOut(duration: 0.6), value: shown)
    }
}

private struct DotRing: View {
    let fraction: Double
    let count: Int
    let color: Color

    var body: some View {
        GeometryReader { g in
            let r = min(g.size.width, g.size.height) / 2
            ForEach(0..<count, id: \.self) { i in
                let t = Double(i) / Double(count)
                let angle = 2 * Double.pi * t
                Circle()
                    .fill(t < fraction ? color : Color.white.opacity(0.2))
                    .frame(width: 4, height: 4)
                    .position(x: g.size.width / 2 + r * sin(angle),
                              y: g.size.height / 2 - r * cos(angle))
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    HeroRing(fraction: 0.7, colors: UsageSnapshot.Level.ok.ringColors) {
        Text("1.32 GB").font(.largeTitle.bold()).foregroundStyle(.white)
    }
    .frame(width: 300, height: 300)
    .padding()
    .background(.black)
}

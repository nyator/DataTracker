import SwiftUI

/// Full-screen detail pages for the Insights cards. Swipe or use the arrows
/// to move between them; each page brings its own colour wash.
struct InsightPager: View {
    @EnvironmentObject private var model: DashboardModel
    @Environment(\.dismiss) private var dismiss
    @State private var page: Insight
    @State private var showLimit = false

    init(start: Insight) {
        _page = State(initialValue: start)
    }

    var body: some View {
        let figures = InsightFigures(snapshot: model.snapshot, settings: model.settings)
        VStack(spacing: 0) {
            topBar(figures)
            TabView(selection: $page) {
                ForEach(Insight.allCases) { insight in
                    ScrollView {
                        InsightPage(insight: insight, figures: figures) { showLimit = true }
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                            .padding(.bottom, 110)
                    }
                    .scrollIndicators(.hidden)
                    .tag(insight)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .overlay(alignment: .bottom) { bottomBar }
        .background(
            WashBackground(color: page.tint.wash)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.35), value: page)
        )
        .preferredColorScheme(.dark)
        .tint(.white)
        .sheet(isPresented: $showLimit) {
            LimitSheet().environmentObject(model)
        }
    }

    private func topBar(_ figures: InsightFigures) -> some View {
        ZStack {
            VStack(spacing: 2) {
                Text(page.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(subtitle(figures))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(.horizontal, 60)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            HStack {
                Button { dismiss() } label: { GlassCircle(systemImage: "xmark") }
                    .accessibilityLabel("Close")
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func subtitle(_ figures: InsightFigures) -> String {
        let s = figures.snapshot
        switch page {
        case .trend, .calendar, .remaining:
            return "Last 14 days"
        case .bundle:
            return "\(s.daysLeft) \(s.daysLeft == 1 ? "day" : "days") left"
        case .pace:
            return "Since \(figures.settings.startDate.formatted(.dateTime.day().month(.abbreviated)))"
        case .plan:
            return figures.settings.useFixedBudget ? "Your own limit" : "Automatic budget"
        }
    }

    private var bottomBar: some View {
        let all = Insight.allCases
        let index = page.rawValue
        return HStack {
            Button { go(to: index - 1) } label: { GlassCircle(systemImage: "chevron.left", size: 52) }
                .opacity(index == 0 ? 0.35 : 1)
                .disabled(index == 0)
                .accessibilityLabel("Previous")
            Spacer()
            HStack(spacing: 7) {
                ForEach(all) { insight in
                    Circle()
                        .fill(Color.white.opacity(insight == page ? 1 : 0.35))
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Capsule().fill(Color.white.opacity(0.14)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
            .accessibilityElement()
            .accessibilityLabel("Page \(index + 1) of \(all.count)")
            Spacer()
            Button { go(to: index + 1) } label: { GlassCircle(systemImage: "chevron.right", size: 52) }
                .opacity(index == all.count - 1 ? 0.35 : 1)
                .disabled(index == all.count - 1)
                .accessibilityLabel("Next")
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 4)
        .background(
            LinearGradient(colors: [Palette.ink.opacity(0), Palette.ink.opacity(0.85)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        )
    }

    private func go(to index: Int) {
        guard let next = Insight(rawValue: index) else { return }
        withAnimation(.easeInOut) { page = next }
    }
}

#Preview {
    InsightPager(start: .trend)
        .environmentObject(DashboardModel())
}

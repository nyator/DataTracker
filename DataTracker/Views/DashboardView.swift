import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: DashboardModel

    var body: some View {
        let s = model.snapshot
        ScrollView {
            VStack(spacing: 12) {
                if !s.hasCellularInterface {
                    NoticeCard(systemImage: "antenna.radiowaves.left.and.right.slash",
                               text: "No cellular interface found. Usage is only measured on an iPhone with mobile data.")
                }
                if s.daysLeft == 0 && !model.settings.useFixedBudget {
                    NoticeCard(systemImage: "calendar.badge.exclamationmark",
                               text: "This bundle's period has ended. Start a new bundle in Settings.")
                }
                if !model.settings.isSetUp {
                    SetupCard(skip: model.skipSetup)
                }

                TodayCard(snapshot: s)
                // Pace is meaningless until real usage so far has been entered.
                BundleCard(snapshot: s, showPace: model.settings.isSetUp,
                           fixedBudget: model.settings.useFixedBudget)
                HistoryCard(snapshot: s)

                Footer(lastSample: s.lastSampleDate)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(Theme.page)
        .refreshable { model.refresh() }
    }
}

/// Title on the left, pill on the right; stacked when they don't fit side by side.
private struct CardHeader: View {
    let title: String
    var pill: String?
    var pillColor: Color = .white

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(title).font(Theme.cardTitle).fixedSize()
                Spacer()
                if let pill { Pill(text: pill, color: pillColor).fixedSize() }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(Theme.cardTitle)
                if let pill { Pill(text: pill, color: pillColor) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
    }
}

private struct TodayCard: View {
    let snapshot: UsageSnapshot

    /// Grows with the text size, capped so it still fits a phone's width.
    @ScaledMetric(relativeTo: .title) private var ringSize: CGFloat = 220

    var body: some View {
        let size = min(ringSize, 290)
        let color = snapshot.level.color
        VStack(spacing: 16) {
            CardHeader(title: "Today", pill: snapshot.level.label, pillColor: color)

            UsageRing(fraction: snapshot.todayFraction, color: color, lineWidth: 16) {
                // Each line stays whole and shrinks to fit inside the ring rather than wrapping.
                VStack(spacing: 4) {
                    Text("Used today")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.secondaryText)
                    figureText(snapshot.todayBytes)
                        .monospacedDigit()
                    Text("of \(DataFormat.string(snapshot.dailyBudgetBytes)) · \(Int((snapshot.todayFraction * 100).rounded()))%")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: size * 0.66)
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity)

            statusLine
                .font(.headline)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .auraCard(glow: color, from: .top)
    }

    private var statusLine: Text {
        if snapshot.todayBytes > snapshot.dailyBudgetBytes {
            return Text(DataFormat.string(snapshot.todayBytes - snapshot.dailyBudgetBytes)).foregroundColor(.white)
                + Text(" over today's budget").foregroundColor(Theme.secondaryText)
        }
        return Text(DataFormat.string(snapshot.todayRemainingBytes)).foregroundColor(.white)
            + Text(" left today").foregroundColor(Theme.secondaryText)
    }
}

private struct BundleCard: View {
    let snapshot: UsageSnapshot
    let showPace: Bool
    let fixedBudget: Bool

    /// Within 100 MB either way counts as on pace.
    private static let tolerance: Int64 = 100 * 1_048_576

    var body: some View {
        let s = snapshot
        let pace = showPace ? s.paceBytes : nil
        let color = (pace ?? 0) < -Self.tolerance ? Theme.orange : Theme.lime
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: "Bundle", pill: "\(s.daysLeft) \(s.daysLeft == 1 ? "day" : "days") left")

            VStack(alignment: .leading, spacing: 2) {
                figureText(s.bundleUsedBytes)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("used of \(DataFormat.string(s.bundleBytes)) · \(DataFormat.string(s.bundleRemainingBytes)) left")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.secondaryText)
            }

            TickMeter(fraction: s.bundleFraction, color: color)

            summary(pace: pace)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .auraCard(glow: pace == nil ? Theme.purple : color.opacity(0.8), from: .bottomLeading)
    }

    /// The kit's "Goal Progress" sentence: grey text with the key facts in white.
    private func summary(pace: Int64?) -> Text {
        let dim = Theme.tertiaryText
        let perDay = Text("\(DataFormat.string(snapshot.recommendedFromTomorrowBytes)) a day").foregroundColor(.white)
        guard let pace else {
            return Text("From tomorrow you can use ").foregroundColor(dim) + perDay
                + Text(fixedBudget ? " to make the bundle last." : ".").foregroundColor(dim)
        }
        if abs(pace) < Self.tolerance {
            return Text("You're ").foregroundColor(dim) + Text("on pace").foregroundColor(.white)
                + Text(". Keep to ").foregroundColor(dim) + perDay + Text(" from tomorrow.").foregroundColor(dim)
        }
        if pace > 0 {
            return Text("You're ").foregroundColor(dim)
                + Text("\(DataFormat.string(pace)) under pace").foregroundColor(.white)
                + Text(" and can use ").foregroundColor(dim) + perDay + Text(" from tomorrow.").foregroundColor(dim)
        }
        return Text("You're ").foregroundColor(dim)
            + Text("\(DataFormat.string(-pace)) over pace").foregroundColor(.white)
            + Text(". Keep to ").foregroundColor(dim) + perDay + Text(" to make it last.").foregroundColor(dim)
    }
}

private struct HistoryCard: View {
    let snapshot: UsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let legend = Label("Budget \(DataFormat.string(snapshot.dailyBudgetBytes))", systemImage: "line.horizontal.3")
                .labelStyle(BudgetLegendStyle())
            // Side by side when they fit; stacked at large text sizes.
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("Last 14 days").font(Theme.cardTitle).fixedSize()
                    Spacer()
                    legend.fixedSize()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last 14 days").font(Theme.cardTitle)
                    legend
                }
            }
            .foregroundStyle(.white)

            HistoryChart(days: snapshot.history, budgetBytes: snapshot.dailyBudgetBytes,
                         todayColor: snapshot.level.color)
                .frame(height: 190)
        }
        .auraCard(glow: Theme.blue.opacity(0.7), from: .topLeading)
    }
}

/// A short dashed line + text, matching the budget line in the chart.
private struct BudgetLegendStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            Path { p in
                p.move(to: CGPoint(x: 0, y: 0.5))
                p.addLine(to: CGPoint(x: 16, y: 0.5))
            }
            .stroke(Theme.secondaryText, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .frame(width: 16, height: 1)
            configuration.title
        }
        .font(Theme.caption)
        .foregroundStyle(Theme.secondaryText)
    }
}

/// First-run prompt: the counters can't see usage from before the app was
/// installed, so ask for the bundle's start date and usage so far.
private struct SetupCard: View {
    let skip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Set up your bundle")
                .font(Theme.cardTitle)
                .foregroundStyle(.white)
            Text("Enter when your bundle started and how much you've used so far (check with MTN, e.g. *138#). Until then, totals only count data used since you installed the app.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            HStack(spacing: 8) {
                NavigationLink {
                    SettingsView()
                } label: {
                    Text("Set up")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(Capsule().fill(.white))
                }
                Button(action: skip) {
                    Text("Skip")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .overlay(Capsule().strokeBorder(.white, lineWidth: 1))
                }
            }
        }
        .auraCard(glow: Theme.purple, from: .topTrailing)
    }
}

private struct NoticeCard: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline)
            .foregroundStyle(.white)
            .auraCard(glow: Theme.orange.opacity(0.7), from: .leading)
    }
}

private struct Footer: View {
    let lastSample: Date?

    var body: some View {
        VStack(spacing: 4) {
            if let lastSample {
                Text("Updated \(lastSample.formatted(.relative(presentation: .named)))")
            }
            Text("Background updates run when iOS allows, roughly every 1–3 hours.")
        }
        .font(.caption2)
        .foregroundStyle(Theme.tertiaryText)
        .multilineTextAlignment(.center)
        .padding(.top, 4)
    }
}

#Preview {
    NavigationStack { DashboardView() }
        .environmentObject(DashboardModel())
        .preferredColorScheme(.dark)
}

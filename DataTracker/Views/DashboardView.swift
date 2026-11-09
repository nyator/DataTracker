import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: DashboardModel
    @State private var showLimit = false
    @State private var openInsight: Insight?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        let s = model.snapshot
        let figures = InsightFigures(snapshot: s, settings: model.settings)
        ScrollView {
            VStack(spacing: 20) {
                Header(snapshot: s, fixedBudget: model.settings.useFixedBudget)

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

                TodayHero(snapshot: s)

                StatRow(snapshot: s, isOwnLimit: model.settings.useFixedBudget) { showLimit = true }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Insights")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .accessibilityAddTraits(.isHeader)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Insight.allCases) { insight in
                            Button {
                                openInsight = insight
                            } label: {
                                InsightCard(insight: insight, figures: figures)
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }
                .padding(.top, 8)

                Footer(lastSample: s.lastSampleDate)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(WashBackground(color: s.level.wash).ignoresSafeArea())
        .animation(.easeInOut(duration: 0.4), value: s.level)
        .refreshable { model.refresh() }
        .sheet(isPresented: $showLimit) { LimitSheet() }
        .fullScreenCover(item: $openInsight) { insight in
            InsightPager(start: insight)
                .environmentObject(model)
        }
    }
}

/// "Monday 9 Nov" in a glass pill, days left under it, and the round
/// Help and Settings buttons on the right.
private struct Header: View {
    let snapshot: UsageSnapshot
    let fixedBudget: Bool

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                (Text(snapshot.date.formatted(.dateTime.weekday(.wide))).fontWeight(.bold)
                 + Text(" " + snapshot.date.formatted(.dateTime.day().month(.abbreviated))))
                    .font(.title3)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.leading, 10)
            }
            Spacer(minLength: 12)
            HStack(spacing: 10) {
                NavigationLink {
                    HelpView()
                } label: {
                    GlassCircle(systemImage: "questionmark")
                }
                .accessibilityLabel("How to use")
                NavigationLink {
                    SettingsView()
                } label: {
                    GlassCircle(systemImage: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
        .padding(.top, 8)
    }

    private var subtitle: String {
        if fixedBudget && snapshot.daysLeft == 0 { return "Your own daily limit" }
        return "\(snapshot.daysLeft) \(snapshot.daysLeft == 1 ? "day" : "days") left in your bundle"
    }
}

/// The ring drains as today's budget is used. Past the budget it refills in
/// pink to show how far over (a quarter ring = 25% over).
private struct TodayHero: View {
    let snapshot: UsageSnapshot

    @ScaledMetric(relativeTo: .largeTitle) private var ringSize: CGFloat = 290

    var body: some View {
        let size = min(ringSize, 330)
        let over = snapshot.isOverToday
        HeroRing(fraction: snapshot.ringFraction, colors: snapshot.level.ringColors) {
            VStack(spacing: 6) {
                figureText(snapshot.ringFigureBytes, font: FigureFont.hero, unitFont: .title3.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(over ? "over today's budget" : "left today")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                HStack(spacing: 6) {
                    Circle().fill(snapshot.level.ringColors.last ?? .white).frame(width: 7, height: 7)
                    Text(snapshot.level.label)
                }
                .font(Theme.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                .padding(.top, 4)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(width: size * 0.56)
        }
        .frame(width: size, height: size)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Daily limit (opens the sheet), used today, and the amount from tomorrow.
private struct StatRow: View {
    let snapshot: UsageSnapshot
    let isOwnLimit: Bool
    let editLimit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: editLimit) {
                stat(isOwnLimit ? "My limit" : "Daily limit", snapshot.dailyBudgetBytes, chevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Set your own daily limit and when you're warned")
            stat("Used today", snapshot.todayBytes)
            stat("From tomorrow", snapshot.recommendedFromTomorrowBytes)
        }
    }

    private func stat(_ label: String, _ bytes: Int64, chevron: Bool = false) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 3) {
                Text(label)
                if chevron { Image(systemName: "chevron.right").imageScale(.small) }
            }
            .font(Theme.caption)
            .foregroundStyle(Theme.secondaryText)
            figureText(bytes, font: FigureFont.stat, unitFont: .footnote)
                .monospacedDigit()
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
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
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(Capsule().fill(.white))
                }
                Button(action: skip) {
                    Text("Skip")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }
            }
        }
        .padding(Theme.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Insight.bundle.tint.card))
    }
}

private struct NoticeCard: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline)
            .foregroundStyle(.white)
            .padding(Theme.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Insight.calendar.tint.card))
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

import SwiftUI

/// "How to use" guide, opened from the dashboard's ? button and from Settings.
struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("DataTracker counts your mobile data, sets a daily budget so your bundle lasts, and warns you before you go over.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)

                ForEach(HelpSection.all) { section in
                    HelpCard(section: section)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(Theme.page)
        .navigationTitle("How to use")
        .navigationBarTitleDisplayMode(.large)
    }
}

private struct HelpSection: Identifiable {
    let id: String
    let icon: String
    let glow: Color
    let steps: [Text]

    var title: String { id }

    /// A step with the key phrase in white and the rest dim, like the dashboard sentences.
    private static func step(_ lead: String, _ rest: String) -> Text {
        Text(lead).foregroundColor(.white) + Text(" " + rest).foregroundColor(Theme.secondaryText)
    }

    static let all: [HelpSection] = [
        HelpSection(id: "Get started", icon: "flag.checkered", glow: Theme.purple, steps: [
            step("Set your bundle.", "In Settings, enter its size, the day you bought it and how many days it lasts."),
            step("Enter what you've used so far.", "Check your balance with MTN (e.g. *138#) and type the total used under Correction. The app can't see data used before it was installed."),
            step("Allow notifications", "so you get the 80% and 100% alerts."),
            step("Keep Background App Refresh on", "(iOS Settings → General → Background App Refresh) so the app can check while you're not using it."),
            step("Add the widget.", "Long-press your Home Screen, tap Edit → Add Widget, and choose DataTracker."),
        ]),
        HelpSection(id: "Reading the dashboard", icon: "gauge.with.dots.needle.67percent", glow: Theme.green, steps: [
            step("Today", "shows how much of today's budget you've used. The colour tells you where you stand: green is on track, orange means you've reached your first alert, pink means you're over."),
            step("Bundle", "shows the whole bundle: how much you've used, what's left, and days remaining. Each lit segment is a slice of the bundle."),
            step("Pace", "compares your usage with an even spread over the bundle. Under pace means you have data in hand; over pace means you'll need to use less to make it last."),
            step("Last 14 days", "shows each day's usage. Today is lit up, days over budget are pink, and the dashed line is today's budget."),
        ]),
        HelpSection(id: "Your daily budget", icon: "calendar", glow: Theme.blue, steps: [
            step("It adapts every day:", "data left at the start of the day ÷ days left. Use less today and tomorrow's budget goes up; use more and it goes down."),
            step("It doesn't shrink during the day.", "Today's budget is fixed at midnight, so using data doesn't move your target."),
            step("Prefer a set amount?", "Tap Daily limit on the Today card, choose My limit and type how much you want to use a day, e.g. 2 GB."),
        ]),
        HelpSection(id: "Alerts", icon: "bell.badge", glow: Theme.orange, steps: [
            step("You're warned at 80% and 100%", "of the day's limit. Change both under Daily limit on the Today card; it shows what each works out to in GB."),
            step("Each alert comes once a day.", "A new day starts fresh at midnight."),
            step("Alerts can arrive late.", "iOS decides when the app runs in the background, usually every 1–3 hours, so an alert can come a while after you cross the line. Opening the app or glancing at the widget checks straight away."),
        ]),
        HelpSection(id: "Keeping it accurate", icon: "checkmark.seal", glow: Theme.lime, steps: [
            step("Re-check with MTN now and then", "and enter the total under Correction. The app continues from that figure."),
            step("Don't swipe the app away", "in the app switcher. iOS then stops its background checks until you open it again."),
            step("Open it or check the widget daily.", "Frequent readings keep the count precise."),
            step("Bought a new bundle?", "Tap Start new bundle today in Settings."),
        ]),
        HelpSection(id: "How it measures", icon: "antenna.radiowaves.left.and.right", glow: Theme.lavender, steps: [
            step("It reads your iPhone's own mobile-data counters", "and adds up the change between readings. No VPN, nothing leaves your phone."),
            step("It counts all mobile data,", "including Personal Hotspot, but not Wi-Fi. It can't show which app used it."),
            step("Restarting your phone is fine.", "The app notices and carries on counting from where it left off."),
        ]),
    ]
}

private struct HelpCard: View {
    let section: HelpSection
    /// Step-number circle grows with the text size so the digit always fits.
    @ScaledMetric(relativeTo: .caption) private var bubble: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(section.title, systemImage: section.icon)
                .font(Theme.cardTitle)
                .foregroundStyle(.white)
            ForEach(Array(section.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(index + 1)")
                        .font(Theme.caption.weight(.semibold))
                        .foregroundStyle(.black)
                        .fixedSize()
                        .frame(width: bubble, height: bubble)
                        .background(Circle().fill(.white))
                        .accessibilityHidden(true)
                    step
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .auraCard(glow: section.glow.opacity(0.6), from: .topTrailing)
    }
}

#Preview {
    NavigationStack { HelpView() }
        .preferredColorScheme(.dark)
}

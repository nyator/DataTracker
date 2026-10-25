import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var model: DashboardModel
    @State private var draft = BudgetSettings()
    @State private var usedSoFarGB: Double?
    @State private var confirmNewBundle = false
    @State private var correctionApplied = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var refreshStatus: UIBackgroundRefreshStatus = .available

    var body: some View {
        Form {
            Section {
                LabeledContent("Size") {
                    TextField("GB", value: $draft.bundleSizeGB, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    Text("GB").foregroundStyle(.secondary)
                }
                DatePicker("Start date", selection: $draft.startDate, displayedComponents: .date)
                Stepper(value: $draft.durationDays, in: 1...365) {
                    LabeledContent("Duration", value: "\(draft.durationDays) days")
                }
                LabeledContent("Ends", value: lastDay.formatted(date: .abbreviated, time: .omitted))
            } header: {
                Text("Bundle")
            }

            Section {
                Toggle("Use my own daily limit", isOn: $draft.useFixedBudget)
                if draft.useFixedBudget {
                    LabeledContent("Daily limit") {
                        TextField("GB", value: $draft.fixedDailyBudgetGB, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text("GB").foregroundStyle(.secondary)
                    }
                } else {
                    LabeledContent("Today's budget", value: DataFormat.string(model.snapshot.dailyBudgetBytes))
                }
            } header: {
                Text("Daily budget")
            } footer: {
                Text(draft.useFixedBudget
                     ? "The same limit every day."
                     : "Data left at the start of the day ÷ days left, so the budget rises if you under-use and falls if you over-use.")
            }

            Section {
                AlertThresholdRows(settings: $draft, budgetBytes: model.effectiveBudget(for: draft))
            } header: {
                Text("Alerts")
            } footer: {
                Text("Each warning comes at most once per day, as a percentage of that day's budget.")
            }

            Section {
                LabeledContent("Used so far") {
                    TextField(String(format: "%.2f", Budget.gb(fromBytes: model.snapshot.bundleUsedBytes)),
                              value: $usedSoFarGB, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    Text("GB").foregroundStyle(.secondary)
                }
                // The button appears once there's a value to apply. A disabled
                // grey button here read like placeholder text.
                if let gb = usedSoFarGB {
                    Button {
                        model.setBundleUsed(gb: gb)
                        usedSoFarGB = nil
                        correctionApplied = true
                        hideKeyboard()
                    } label: {
                        Label("Apply: set used to \(gb.formatted(.number.precision(.fractionLength(0...2)))) GB",
                              systemImage: "checkmark.circle")
                    }
                } else if correctionApplied {
                    Label("Bundle usage updated", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                Button("Start new bundle today", role: .destructive) { confirmNewBundle = true }
            } header: {
                Text("Correction")
            } footer: {
                Text("Check your balance with MTN (e.g. *138#) and enter the bundle total used so far. Tracking continues from that figure.")
            }

            Section {
                StatusRow(title: "Notifications", ok: notificationStatus == .authorized || notificationStatus == .provisional,
                          detail: notificationText)
                StatusRow(title: "Background App Refresh", ok: refreshStatus == .available,
                          detail: refreshStatus == .available ? "On" : "Off: alerts only update when you open the app")
                LabeledContent("Last background run") {
                    if let last = BackgroundRefresh.lastRunDate {
                        Text("\(last.formatted(.relative(presentation: .named))) · \(BackgroundRefresh.runCount) total")
                    } else {
                        Text("Not yet")
                    }
                }
                if notificationStatus == .denied || refreshStatus != .available {
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
            } header: {
                Text("Permissions")
            }

            Section {
                NavigationLink {
                    HelpView()
                } label: {
                    Label("How to use DataTracker", systemImage: "questionmark.circle")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.page)
        .navigationTitle("Settings")
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { hideKeyboard() }
            }
        }
        .onAppear { draft = model.settings }
        .onChange(of: draft) { _, newValue in model.update(sanitized(newValue)) }
        .onChange(of: usedSoFarGB) { _, newValue in
            if newValue != nil { correctionApplied = false }
        }
        .confirmationDialog("Start a new bundle today?", isPresented: $confirmNewBundle, titleVisibility: .visible) {
            Button("Start new bundle", role: .destructive) {
                model.startNewBundleToday()
                draft = model.settings
            }
        } message: {
            Text("Sets the start date to today and bundle usage to 0. Daily history is kept.")
        }
        .task { await refreshPermissionStatus() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await refreshPermissionStatus() }
        }
    }

    private var lastDay: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: Budget.endDate(draft)) ?? draft.startDate
    }

    private var notificationText: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: return "On"
        case .denied: return "Off: you won't get budget alerts"
        default: return "Not requested yet"
        }
    }

    private func sanitized(_ s: BudgetSettings) -> BudgetSettings {
        var s = s
        s.bundleSizeGB = max(s.bundleSizeGB, 0)
        s.fixedDailyBudgetGB = max(s.fixedDailyBudgetGB, 0)
        s.durationDays = max(s.durationDays, 1)
        return s
    }

    private func refreshPermissionStatus() async {
        notificationStatus = await Notifier.authorizationStatus()
        refreshStatus = UIApplication.shared.backgroundRefreshStatus
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

private struct StatusRow: View {
    let title: String
    let ok: Bool
    let detail: String

    var body: some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .orange)
            VStack(alignment: .leading) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

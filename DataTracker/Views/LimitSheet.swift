import SwiftUI

/// "Daily limit" sheet, opened from the Today card: choose an automatic budget
/// or type your own limit, and when to be warned.
struct LimitSheet: View {
    @EnvironmentObject private var model: DashboardModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = BudgetSettings()

    private static let presets: [Double] = [1, 1.5, 2, 2.5, 3]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Limit", selection: $draft.useFixedBudget) {
                        Text("Automatic").tag(false)
                        Text("My limit").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                    if draft.useFixedBudget {
                        LabeledContent("Daily limit") {
                            TextField("GB", value: $draft.fixedDailyBudgetGB,
                                      format: .number.precision(.fractionLength(0...2)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .font(.title3.weight(.medium))
                            Text("GB").foregroundStyle(.secondary)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Self.presets, id: \.self) { gb in
                                    let selected = abs(draft.fixedDailyBudgetGB - gb) < 0.001
                                    Button {
                                        draft.fixedDailyBudgetGB = gb
                                    } label: {
                                        Text("\(gb.formatted(.number.precision(.fractionLength(0...1)))) GB")
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(selected ? .black : .white)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 8)
                                            .background(Capsule().fill(selected ? Color.white : Theme.overlay))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    } else {
                        LabeledContent("Today's limit", value: DataFormat.string(model.autoBudget(for: draft)))
                    }
                } footer: {
                    Text(draft.useFixedBudget
                         ? "The same limit every day. You're warned as you approach it."
                         : "Worked out each morning from what's left of your bundle ÷ days left, so your bundle lasts to the end.")
                }

                Section {
                    AlertThresholdRows(settings: $draft, budgetBytes: model.effectiveBudget(for: draft))
                } header: {
                    Text("Warn me at")
                } footer: {
                    Text("Each warning comes at most once a day.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.page)
            .navigationTitle("Daily limit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.update(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    // A limit of 0 would mean no warnings ever fire.
                    .disabled(draft.useFixedBudget && draft.fixedDailyBudgetGB <= 0)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            .onAppear { draft = model.settings }
        }
        .preferredColorScheme(.dark)
        .tint(.white)
    }
}

/// The two warning thresholds, each shown as a percentage and the GB it works out to.
/// Shared by Settings and the Daily limit sheet.
struct AlertThresholdRows: View {
    @Binding var settings: BudgetSettings
    let budgetBytes: Int64

    var body: some View {
        Stepper(value: $settings.warningPercent, in: 10...200, step: 5) {
            row("First warning", settings.warningPercent)
        }
        Stepper(value: $settings.limitPercent, in: 10...200, step: 5) {
            row("Second warning", settings.limitPercent)
        }
    }

    private func row(_ title: String, _ percent: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text("\(percent)% · \(DataFormat.string(budgetBytes * Int64(percent) / 100))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

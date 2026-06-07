import SwiftUI

struct AutomationSettingsTab: View {
    @State private var automation = AutomationPreferences.shared

    var body: some View {
        Form {
            Toggle(L10n.t(.enableAutomation), isOn: $automation.automationEnabled)

            if automation.automationEnabled {
                Section(L10n.t(.monthlyFetch)) {
                    Toggle(L10n.t(.monthlyFetch), isOn: $automation.autoFetchEnabled)

                    if automation.autoFetchEnabled {
                        LabeledContent(L10n.t(.scheduleDay)) {
                            Picker("", selection: $automation.fetchDay) {
                                Text(L10n.t(.anytime)).tag(-1)
                                ForEach(1 ... 28, id: \.self) { d in
                                    Text("\(d)").tag(d)
                                }
                            }
                            .labelsHidden()
                        }

                        if automation.fetchDay > 0 {
                            timePicker(
                                hour: $automation.fetchHour,
                                minute: $automation.fetchMinute
                            )
                        }
                    }
                }

                Section(L10n.t(.dailyRecommend)) {
                    Toggle(L10n.t(.dailyRecommend), isOn: $automation.autoRecommendEnabled)

                    if automation.autoRecommendEnabled {
                        timePicker(
                            hour: $automation.recommendHour,
                            minute: $automation.recommendMinute
                        )
                    }
                }
            }

            Section(L10n.t(.automationHistory)) {
                LabeledContent(L10n.t(.lastMonthlyFetch)) {
                    Text(timestamp(automation.lastAutoFetchAt))
                        .foregroundStyle(.secondary)
                }
                LabeledContent(L10n.t(.lastDailyRecommend)) {
                    Text(timestamp(automation.lastAutoRecommendAt))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func timePicker(hour: Binding<Int>, minute: Binding<Int>) -> some View {
        HStack(spacing: 4) {
            Picker("", selection: hour) {
                Text(L10n.t(.anytime)).tag(-1)
                ForEach(0 ... 23, id: \.self) { h in
                    Text(String(format: "%02d", h)).tag(h)
                }
            }
            .labelsHidden()
            .frame(width: 80)

            if hour.wrappedValue >= 0 {
                Text(":")
                    .foregroundStyle(.secondary)

                Picker("", selection: minute) {
                    ForEach(0 ... 59, id: \.self) { m in
                        Text(String(format: "%02d", m)).tag(m)
                    }
                }
                .labelsHidden()
                .frame(width: 80)
            }
        }
    }

    private func timestamp(_ date: Date?) -> String {
        guard let date else { return L10n.t(.never) }
        return date.formatted(.dateTime.year().month().day().hour().minute())
    }
}

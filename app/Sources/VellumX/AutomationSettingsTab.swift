import SwiftUI

struct AutomationSettingsTab: View {
    @State private var automation = AutomationPreferences.shared

    var body: some View {
        Form {
            Section(L10n.t(.automationTasks)) {
                Toggle(L10n.t(.enableAutomation), isOn: $automation.automationEnabled)
                Toggle(L10n.t(.monthlyFetch), isOn: $automation.autoFetchEnabled)
                Toggle(L10n.t(.dailyRecommend), isOn: $automation.autoRecommendEnabled)
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

    private func timestamp(_ date: Date?) -> String {
        guard let date else { return L10n.t(.never) }
        return date.formatted(.dateTime.year().month().day().hour().minute())
    }
}

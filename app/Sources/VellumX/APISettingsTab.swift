import SwiftUI

struct APISettingsTab: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section(L10n.t(.deepseekSection)) {
                Toggle(L10n.t(.enableTranslation), isOn: $settings.translateEnabled)
                SecureField("API Key", text: $settings.deepSeekAPIKey)
                Text(L10n.t(.apiKeyHint))
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Base URL", text: $settings.deepSeekBaseURL)
                TextField(L10n.t(.model), text: $settings.deepSeekModel)
                TextField(L10n.t(.targetLanguage), text: $settings.targetLanguage)
            }
        }
        .formStyle(.grouped)
    }
}

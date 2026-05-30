import SwiftUI

struct APISettingsTab: View {
    @State private var settings = AppSettings.shared
    @State private var isTestingConnection = false
    @State private var connectionMessage: String?
    @State private var connectionIsError = false

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
                HStack {
                    Button {
                        testConnection()
                    } label: {
                        if isTestingConnection {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(L10n.t(.testConnection))
                        }
                    }
                    .disabled(isTestingConnection)

                    if let connectionMessage {
                        Text(connectionMessage)
                            .font(.caption)
                            .foregroundStyle(connectionIsError ? .red : .green)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func testConnection() {
        isTestingConnection = true
        connectionIsError = false
        connectionMessage = L10n.t(.testingConnection)

        Task {
            do {
                let config = ConfigManager.shared.effectiveConfig
                let apiKey = settings.deepSeekAPIKey.isEmpty
                    ? (ProcessInfo.processInfo.environment[config.translate.api_key_env] ?? "")
                    : settings.deepSeekAPIKey
                let translator = DeepSeekTranslator(config: config, apiKey: apiKey)
                let models = try await translator.fetchModels()
                connectionIsError = false
                connectionMessage = "\(L10n.t(.connectionOK)) · \(models.count) models"
            } catch {
                connectionIsError = true
                connectionMessage = "\(L10n.t(.connectionFailed)): \(error.localizedDescription)"
            }
            isTestingConnection = false
        }
    }
}

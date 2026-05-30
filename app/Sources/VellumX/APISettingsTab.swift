import SwiftUI

struct APISettingsTab: View {
    @State private var settings = AppSettings.shared
    @State private var isTestingConnection = false
    @State private var connectionMessage: String?
    @State private var connectionIsError = false
    @State private var isLoadingModels = false
    @State private var availableModels: [String] = []
    @State private var modelMessage: String?
    @State private var modelIsError = false

    var body: some View {
        Form {
            Section(L10n.t(.deepseekSection)) {
                Toggle(L10n.t(.enableTranslation), isOn: $settings.translateEnabled)
                SecureField("API Key", text: $settings.deepSeekAPIKey)
                    .onSubmit { loadModels() }
                Text(L10n.t(.apiKeyHint))
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Base URL", text: $settings.deepSeekBaseURL)
                    .onSubmit { loadModels() }
                Picker(L10n.t(.model), selection: $settings.deepSeekModel) {
                    if availableModels.isEmpty {
                        Text(settings.deepSeekModel.isEmpty ? L10n.t(.modelsUnavailable) : settings.deepSeekModel)
                            .tag(settings.deepSeekModel)
                    } else {
                        ForEach(availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                }
                .disabled(availableModels.isEmpty)
                HStack {
                    Button {
                        loadModels()
                    } label: {
                        if isLoadingModels {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(L10n.t(.refreshModels))
                        }
                    }
                    .disabled(isLoadingModels)

                    if let modelMessage {
                        Text(modelMessage)
                            .font(.caption)
                            .foregroundStyle(modelIsError ? .red : .secondary)
                    }
                }
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
        .onAppear {
            if availableModels.isEmpty, !settings.deepSeekAPIKey.isEmpty {
                loadModels()
            }
        }
    }

    private func testConnection() {
        isTestingConnection = true
        connectionIsError = false
        connectionMessage = L10n.t(.testingConnection)

        Task {
            do {
                let models = try await fetchModels()
                apply(models: models)
                connectionIsError = false
                connectionMessage = "\(L10n.t(.connectionOK)) · \(models.count) models"
            } catch {
                connectionIsError = true
                connectionMessage = "\(L10n.t(.connectionFailed)): \(error.localizedDescription)"
            }
            isTestingConnection = false
        }
    }

    private func loadModels() {
        guard !isLoadingModels else { return }
        isLoadingModels = true
        modelIsError = false
        modelMessage = L10n.t(.loadingModels)

        Task {
            do {
                let models = try await fetchModels()
                apply(models: models)
                modelIsError = false
                modelMessage = "\(L10n.t(.modelsLoaded)) · \(models.count)"
            } catch {
                modelIsError = true
                modelMessage = error.localizedDescription
            }
            isLoadingModels = false
        }
    }

    private func fetchModels() async throws -> [String] {
        let config = ConfigManager.shared.effectiveConfig
        let apiKey = settings.deepSeekAPIKey.isEmpty
            ? (ProcessInfo.processInfo.environment[config.translate.api_key_env] ?? "")
            : settings.deepSeekAPIKey
        let translator = DeepSeekTranslator(config: config, apiKey: apiKey)
        return try await translator.fetchModels()
    }

    private func apply(models: [String]) {
        availableModels = models
        if !models.isEmpty, !models.contains(settings.deepSeekModel) {
            settings.deepSeekModel = models[0]
        }
    }
}

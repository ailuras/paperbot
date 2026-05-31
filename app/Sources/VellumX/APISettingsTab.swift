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
                TextField(L10n.t(.targetLanguage), text: $settings.targetLanguage)
            }

            Section(L10n.t(.apiConnection)) {
                LabeledContent(L10n.t(.apiKey)) {
                    HStack(spacing: 8) {
                        SecureField("", text: $settings.deepSeekAPIKey)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { loadModels() }

                        Button {
                            testConnection()
                        } label: {
                            if isTestingConnection {
                                ProgressView().controlSize(.small)
                            } else {
                                Label(L10n.t(.testConnection), systemImage: "checkmark.circle")
                            }
                        }
                        .controlSize(.small)
                        .disabled(isTestingConnection)
                    }
                }

                LabeledContent(L10n.t(.baseURL)) {
                    TextField("", text: $settings.deepSeekBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { loadModels() }
                }

                if let connectionMessage {
                    statusText(connectionMessage, isError: connectionIsError, successColor: .green)
                }

                Text(L10n.t(.apiKeyHint))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.t(.modelSelection)) {
                LabeledContent(L10n.t(.model)) {
                    HStack(spacing: 8) {
                        Picker("", selection: $settings.deepSeekModel) {
                            if availableModels.isEmpty {
                                Text(settings.deepSeekModel.isEmpty ? L10n.t(.modelsUnavailable) : settings.deepSeekModel)
                                    .tag(settings.deepSeekModel)
                            } else {
                                ForEach(availableModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .disabled(availableModels.isEmpty)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            loadModels()
                        } label: {
                            if isLoadingModels {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .controlSize(.small)
                        .disabled(isLoadingModels)
                        .help(L10n.t(.refreshModels))
                    }
                }

                if let modelMessage {
                    statusText(modelMessage, isError: modelIsError, successColor: .secondary)
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

    private func statusText(_ text: String, isError: Bool, successColor: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isError ? "exclamationmark.triangle" : "checkmark.circle")
                .font(.caption)
            Text(text)
                .font(.caption)
                .lineLimit(2)
        }
        .foregroundStyle(isError ? .red : successColor)
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
        let translator = DeepSeekTranslator(config: config, apiKey: settings.deepSeekAPIKey)
        return try await translator.fetchModels()
    }

    private func apply(models: [String]) {
        availableModels = models
        if !models.isEmpty, !models.contains(settings.deepSeekModel) {
            settings.deepSeekModel = models[0]
        }
    }
}

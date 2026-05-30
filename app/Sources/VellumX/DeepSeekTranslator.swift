import Foundation

@MainActor
class DeepSeekTranslator {
    let config: AppConfig
    
    init(config: AppConfig = ConfigManager.shared.effectiveConfig) {
        self.config = config
    }
    
    private func callDeepSeek(text: String, systemPrompt: String) async throws -> String {
        // Prefer the key entered in Settings (stored in the Keychain); fall back
        // to the environment variable for backward compatibility.
        let apiKey = AppSettings.shared.deepSeekAPIKey.isEmpty
            ? (ProcessInfo.processInfo.environment[config.translate.api_key_env] ?? "")
            : AppSettings.shared.deepSeekAPIKey
        if apiKey.isEmpty {
            throw NSError(domain: "DeepSeekTranslator", code: 401, userInfo: [NSLocalizedDescriptionKey: "DeepSeek API key not set — add it in Settings ▸ API"])
        }
        
        let baseUrl = config.translate.base_url
        let model = config.translate.model
        let url = URL(string: "\(baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/chat/completions")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "temperature": 0.3,
            "max_tokens": 2048
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw NSError(domain: "DeepSeekTranslator", code: status, userInfo: [NSLocalizedDescriptionKey: "Bad response status: \(status)"])
        }
        
        // Parse JSON response manually
        struct ChatCompletionResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    var content: String
                }
                var message: Message
            }
            var choices: [Choice]
        }
        
        let decoder = JSONDecoder()
        let result = try decoder.decode(ChatCompletionResponse.self, from: data)
        return result.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    
    func translate(paper: Paper) async throws {
        // Cache check
        if !paper.titleZh.isEmpty {
            print("Translation cache hit for paper \(paper.id)")
            return
        }
        
        let targetLang = config.translate.target_language
        
        let titlePrompt = "You are a professional academic translator. Translate the following paper title into \(targetLang). Preserve technical terms in English where appropriate. Return ONLY the translated title, no explanations."
        let abstractPrompt = "You are a professional academic translator. Translate the following paper abstract into \(targetLang). Preserve technical terms in English where appropriate. Return ONLY the translated text, no explanations."
        
        print("Translating paper title to \(targetLang)...")
        let titleZh = try await callDeepSeek(text: paper.title, systemPrompt: titlePrompt)
        
        var abstractZh = ""
        if !paper.abstract.isEmpty {
            print("Translating paper abstract to \(targetLang)...")
            abstractZh = try await callDeepSeek(text: paper.abstract, systemPrompt: abstractPrompt)
        }
        
        paper.titleZh = titleZh
        paper.abstractZh = abstractZh
        
        // Save automatically to SQLite
        PaperStore.shared.setPaperTranslation(id: paper.id, titleZh: titleZh, abstractZh: abstractZh)
    }
}

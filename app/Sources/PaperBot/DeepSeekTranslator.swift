import Foundation

@MainActor
class DeepSeekTranslator {
    let config: AppConfig
    
    init(config: AppConfig = ConfigManager.shared.config ?? AppConfig(
        openalex: OpenAlexConfig(base_url: "", mailto: "", api_key_env: "", timeout_seconds: 0, per_page: 0, default_days: 0, default_max_results: 0, topic_filter: ""),
        tracks: [:],
        scoring: ScoringConfig(tiers: [:], citation_breakpoints: [], max_citation_points: 0),
        recommendation: RecommendationConfig(daily_count: 0, quality_slots: 0, high_score_threshold: 0, recent_days: 0),
        translate: TranslateConfig(enabled: false, target_language: "中文", model: "deepseek-v4-flash", include_in_email: true, api_key_env: "DEEPSEEK_API_KEY", base_url: "https://api.deepseek.com"),
        mail: MailConfig(smtp_host: "", smtp_port: 0, smtp_user: "", smtp_password: "", from_addr: "", to_addrs: [], use_tls: false, dashboard_url: "")
    )) {
        self.config = config
    }
    
    private func callDeepSeek(text: String, systemPrompt: String) async throws -> String {
        let apiKey = ProcessInfo.processInfo.environment[config.translate.api_key_env] ?? ""
        if apiKey.isEmpty {
            throw NSError(domain: "DeepSeekTranslator", code: 401, userInfo: [NSLocalizedDescriptionKey: "DeepSeek API Key not set in environment variable \(config.translate.api_key_env)"])
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
        
        // Save automatically
        PaperStore.shared.savePapers()
    }
}

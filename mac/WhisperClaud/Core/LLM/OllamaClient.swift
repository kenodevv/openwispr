import Foundation

/// Free local alternative to Claude: Ollama's chat endpoint with the same prompts.
actor OllamaClient {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        session = URLSession(configuration: config)
    }

    func complete(systemStatic: String, systemDynamic: String, user: String,
                  baseURL: String, model: String, maxTokens: Int = 2048) async throws -> ClaudeResult {
        guard let url = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/chat") else {
            throw ClaudeError.server(0, "Ungültige Ollama-URL")
        }
        let system = systemDynamic.isEmpty ? systemStatic : systemStatic + "\n\n" + systemDynamic
        let body: [String: Any] = [
            "model": model,
            "stream": false,
            "think": false,
            "options": ["temperature": 0.1, "num_predict": maxTokens],
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let started = Date()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ClaudeError.network("Ollama nicht erreichbar (\(baseURL)): \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else { throw ClaudeError.badResponse }
        guard http.statusCode == 200 else {
            throw ClaudeError.server(http.statusCode, String(data: data, encoding: .utf8)?.prefix(200).description ?? "Ollama-Fehler")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let text = message["content"] as? String else { throw ClaudeError.badResponse }
        return ClaudeResult(text: text, stopReason: "end_turn", model: model, inputTokens: 0, outputTokens: 0,
                            cacheReadTokens: 0, latencyMs: Int(Date().timeIntervalSince(started) * 1000))
    }
}

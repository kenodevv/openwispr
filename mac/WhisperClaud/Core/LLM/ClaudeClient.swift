import Foundation

struct ClaudeCredentials: Sendable {
    let apiKey: String
    let workspaceId: String?

    static func fromKeychain() -> ClaudeCredentials? {
        guard let key = Keychain.read(Keychain.apiKeyAccount) else { return nil }
        return ClaudeCredentials(apiKey: key, workspaceId: Keychain.read(Keychain.workspaceAccount))
    }
}

struct ClaudeResult: Sendable {
    let text: String
    let stopReason: String
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let latencyMs: Int
}

enum ClaudeError: LocalizedError {
    case missingKey
    case unauthorized(String)
    case rateLimited
    case server(Int, String)
    case network(String)
    case badResponse
    case refused(String)

    var errorDescription: String? {
        switch self {
        case .missingKey: return "No Claude API key stored."
        case .unauthorized(let m): return "API key rejected: \(m)"
        case .rateLimited: return "Rate limit hit, please wait a moment."
        case .server(let code, let m): return "Claude API error \(code): \(m)"
        case .network(let m): return "No connection: \(m)"
        case .badResponse: return "Unexpected response from the Claude API."
        case .refused(let m): return "Claude declined: \(m)"
        }
    }
}

/// Minimal Messages-API client (raw HTTP, there is no official Swift SDK).
actor ClaudeClient {
    private let session: URLSession
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 90
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
    }

    func complete(systemStatic: String, systemDynamic: String, user: String,
                  model: ClaudeModel, effort: Effort, maxTokens: Int = 2048,
                  credentials: ClaudeCredentials) async throws -> ClaudeResult {
        var system = [SystemBlock(text: systemStatic, cache_control: .init())]
        if !systemDynamic.isEmpty { system.append(SystemBlock(text: systemDynamic, cache_control: nil)) }
        let body = RequestBody(
            model: model.rawValue,
            max_tokens: maxTokens,
            system: system,
            messages: [Message(role: "user", content: user)],
            output_config: OutputConfig(effort: effort.rawValue),
            fallbacks: model.supportsServerFallbacks ? "default" : nil)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(credentials.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if model.supportsServerFallbacks {
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        if let workspace = credentials.workspaceId, !workspace.isEmpty {
            request.setValue(workspace, forHTTPHeaderField: "anthropic-workspace-id")
        }
        request.httpBody = try JSONEncoder().encode(body)

        var attempt = 0
        while true {
            attempt += 1
            let started = Date()
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                throw ClaudeError.network(error.localizedDescription)
            }
            guard let http = response as? HTTPURLResponse else { throw ClaudeError.badResponse }
            let latency = Int(Date().timeIntervalSince(started) * 1000)

            switch http.statusCode {
            case 200:
                return try parse(data, latencyMs: latency)
            case 401, 403:
                throw ClaudeError.unauthorized(errorMessage(data))
            case 429:
                if attempt < 2 {
                    let retryAfter = Double(http.value(forHTTPHeaderField: "retry-after") ?? "") ?? 1.5
                    try await Task.sleep(for: .seconds(min(retryAfter, 4)))
                    continue
                }
                throw ClaudeError.rateLimited
            case 500..<600 where attempt < 2:
                try await Task.sleep(for: .seconds(1))
                continue
            default:
                throw ClaudeError.server(http.statusCode, errorMessage(data))
            }
        }
    }

    private func parse(_ data: Data, latencyMs: Int) throws -> ClaudeResult {
        guard let body = try? JSONDecoder().decode(ResponseBody.self, from: data) else { throw ClaudeError.badResponse }
        let stop = body.stop_reason ?? "end_turn"
        if stop == "refusal" {
            throw ClaudeError.refused(body.stop_details?.explanation ?? body.stop_details?.category ?? "safety filter")
        }
        let text = body.content.compactMap { $0.type == "text" ? $0.text : nil }.joined()
        return ClaudeResult(
            text: text,
            stopReason: stop,
            model: body.model ?? "",
            inputTokens: body.usage?.input_tokens ?? 0,
            outputTokens: body.usage?.output_tokens ?? 0,
            cacheReadTokens: body.usage?.cache_read_input_tokens ?? 0,
            latencyMs: latencyMs)
    }

    private func errorMessage(_ data: Data) -> String {
        if let body = try? JSONDecoder().decode(ErrorBody.self, from: data) { return body.error.message }
        return String(data: data, encoding: .utf8)?.prefix(200).description ?? "unknown"
    }

    // MARK: - Wire types (property names are the JSON keys)

    private struct RequestBody: Encodable {
        let model: String
        let max_tokens: Int
        let system: [SystemBlock]
        let messages: [Message]
        let output_config: OutputConfig
        let fallbacks: String?
    }

    private struct SystemBlock: Encodable {
        var type = "text"
        let text: String
        let cache_control: CacheControl?
        struct CacheControl: Encodable { var type = "ephemeral" }
    }

    private struct Message: Encodable {
        let role: String
        let content: String
    }

    private struct OutputConfig: Encodable {
        let effort: String
    }

    private struct ResponseBody: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }
        struct Usage: Decodable {
            let input_tokens: Int?
            let output_tokens: Int?
            let cache_read_input_tokens: Int?
        }
        struct StopDetails: Decodable {
            let category: String?
            let explanation: String?
        }
        let content: [Block]
        let stop_reason: String?
        let stop_details: StopDetails?
        let model: String?
        let usage: Usage?
    }

    private struct ErrorBody: Decodable {
        struct Inner: Decodable {
            let type: String
            let message: String
        }
        let error: Inner
    }
}

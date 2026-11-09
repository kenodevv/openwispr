import Foundation

enum MinimalEdits {
    static let schema = #"{"type":"object","properties":{"edits":{"type":"array","items":{"type":"object","properties":{"from":{"type":"string"},"to":{"type":"string"}},"required":["from","to"],"additionalProperties":false}}},"required":["edits"],"additionalProperties":false}"#

    private struct Reply: Decodable {
        struct Edit: Decodable {
            let from: String
            let to: String
        }
        let edits: [Edit]
    }

    /// Nil means the reply is not the expected JSON; the caller then keeps the transcript.
    static func parse(_ json: String) -> [TextEdit]? {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: Data(json.utf8)) else { return nil }
        return reply.edits.map { TextEdit(from: $0.from, to: $0.to) }
    }
}

enum MinimalDictation {
    private static let minWordsForModel = 3
    private static let maxTokens = 2048

    struct Outcome {
        let normalized: String
        let text: String
        let decisions: [EditDecision]
        let result: ClaudeResult?
        let failure: String?
    }

    /// Never throws for model trouble: any failure leaves the normalized transcript.
    /// `complete` receives system, dynamic system, user message, JSON schema and max tokens.
    static func run(raw: String, dictionary: [DictionaryHint], frozen: [String] = [],
                    complete: (String, String, String, String, Int) async throws -> ClaudeResult) async -> Outcome {
        let normalized = TranscriptNormalizer.normalize(raw, dictionary: dictionary)
        if EditGuard.words(normalized).count < minWordsForModel {
            return Outcome(normalized: normalized, text: normalized, decisions: [], result: nil, failure: nil)
        }

        let result: ClaudeResult
        do {
            result = try await complete(FlowPrompts.dictationMinimalSystem, FlowPrompts.minimalDynamic(dictionary: dictionary),
                                        FlowPrompts.dictationUser(transcript: normalized), MinimalEdits.schema, maxTokens)
        } catch {
            return Outcome(normalized: normalized, text: normalized, decisions: [], result: nil, failure: error.localizedDescription)
        }

        guard let edits = MinimalEdits.parse(result.text) else {
            return Outcome(normalized: normalized, text: normalized, decisions: [], result: result, failure: "reply was not valid edit JSON")
        }
        let guarded = EditGuard.apply(normalized, edits: edits, glossary: CodingGlossary.with(dictionary), frozen: frozen)
        return Outcome(normalized: normalized, text: guarded.text, decisions: guarded.decisions, result: result, failure: nil)
    }
}

import XCTest
@testable import OpenWispr

final class FlowFormatterTests: XCTestCase {
    func testSnippetsRoundTrip() {
        let snippets = [SnippetDef(trigger: "meine Signatur", content: "Viele Grüße\nKeno")]
        let result = FlowFormatter.applySnippets("danke und dann Meine Signatur bitte", snippets: snippets)
        XCTAssertEqual(result.text, "danke und dann {{SNIPPET_1}} bitte")
        XCTAssertEqual(FlowFormatter.restoreSnippets("Danke. {{SNIPPET_1}}", placeholders: result.placeholders), "Danke. Viele Grüße\nKeno")
    }

    func testPostprocessStripsWrappingQuotesAndFences() {
        XCTAssertEqual(FlowFormatter.postprocess("\"Hallo Welt.\"", raw: "hallo welt"), "Hallo Welt.")
        XCTAssertEqual(FlowFormatter.postprocess("```\nHallo Welt.\n```", raw: "hallo welt"), "Hallo Welt.")
        XCTAssertEqual(FlowFormatter.postprocess("Er sagte \"hi\" und ging.", raw: "er sagte hi"), "Er sagte \"hi\" und ging.")
    }

    func testRawCleanupAppliesDictionaryAndPunctuation() {
        let hints = [DictionaryHint(term: "ShiftProxies", misspellings: ["shift proxys", "schiff proxies"])]
        XCTAssertEqual(FlowFormatter.rawCleanup("wir bauen shift proxys heute fertig", dictionary: hints), "Wir bauen ShiftProxies heute fertig.")
    }

    func testSmartSpacing() {
        XCTAssertEqual(FlowFormatter.withSmartSpacing("neuer Satz", before: "Alter Satz."), " neuer Satz")
        XCTAssertEqual(FlowFormatter.withSmartSpacing("neuer Satz", before: "Alter Satz. "), "neuer Satz")
        XCTAssertEqual(FlowFormatter.withSmartSpacing("neuer Satz", before: ""), "neuer Satz")
        XCTAssertEqual(FlowFormatter.withSmartSpacing(", also", before: "Ja"), ", also")
    }

    func testAppCategories() {
        XCTAssertEqual(AppCategory.categorize(bundleId: "com.tinyspeck.slackmacgap", windowTitle: ""), .chat)
        XCTAssertEqual(AppCategory.categorize(bundleId: "com.apple.Terminal", windowTitle: ""), .code)
        XCTAssertEqual(AppCategory.categorize(bundleId: "com.google.Chrome", windowTitle: "Brief – Google Docs"), .documents)
        XCTAssertEqual(AppCategory.categorize(bundleId: "com.example.unknown", windowTitle: ""), .other)
    }

    func testPromptIncludesDictionaryAndContext() {
        var ctx = FocusContext()
        ctx.appName = "Slack"
        ctx.bundleId = "com.tinyspeck.slackmacgap"
        let block = FlowPrompts.dynamicBlock(context: ctx, dictionary: [DictionaryHint(term: "Louven", misspellings: ["Luven"])], hasSnippets: true, language: .de)
        XCTAssertTrue(block.contains("Louven (often misheard as: Luven)"))
        XCTAssertTrue(block.contains("category: chat"))
        XCTAssertTrue(block.contains("{{SNIPPET_n}}"))
        XCTAssertTrue(block.contains("German"))
    }
}

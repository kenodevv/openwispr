import XCTest
@testable import OpenWispr

/// Same cases as windows/OpenWispr.Core.Tests/MinimalDictationTests.cs, so that both apps keep the same promise.
final class MinimalDictationTests: XCTestCase {
    private let glossary = CodingGlossary.with([])

    private func run(_ text: String, _ edits: (String, String)...) -> GuardResult {
        EditGuard.apply(text, edits: edits.map { TextEdit(from: $0.0, to: $0.1) }, glossary: glossary)
    }

    private func verdict(_ text: String, _ from: String, _ to: String) -> EditVerdict {
        run(text, (from, to)).decisions[0].verdict
    }

    private func reply(_ text: String) -> ClaudeResult {
        ClaudeResult(text: text, stopReason: "end_turn", model: "fake", inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, latencyMs: 0)
    }

    private struct Boom: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    func testRepairsMisheardWord() {
        let result = run("Starte das mit Obus und schau nach.", ("Obus", "Opus"))
        XCTAssertEqual(result.text, "Starte das mit Opus und schau nach.")
        XCTAssertEqual(result.decisions[0].verdict, .applied)
    }

    func testAcceptsPhraseRepairWithSharedWord() {
        XCTAssertEqual(run("Test alles voll aus Norm bitte.", ("voll aus Norm", "voll autonom")).text, "Test alles voll autonom bitte.")
    }

    func testRejectsTranslations() {
        for (text, from, to) in [("Gib mir Access auf alles.", "Access", "Zugriff"), ("Plan von Scratch neu ansehen.", "Scratch", "Grund auf")] {
            let result = run(text, (from, to))
            XCTAssertEqual(result.decisions[0].verdict, .notSimilar, from)
            XCTAssertEqual(result.text, text)
        }
    }

    func testProtectedWordsStay() {
        for (from, to) in [("selber", "selbst"), ("halt", "bitte")] {
            let text = "Das machst du \(from) jetzt."
            XCTAssertEqual(verdict(text, from, to), .protected, from)
            XCTAssertEqual(run(text, (from, to)).text, text)
        }
    }

    func testAmbiguousFromIsRejectedAndAnchorResolvesIt() {
        let text = "Die Loks sind weg und die Loks kommen."
        XCTAssertEqual(verdict(text, "Loks", "Logs"), .ambiguous)
        XCTAssertEqual(run(text, ("die Loks kommen", "die Logs kommen")).text, "Die Loks sind weg und die Logs kommen.")
    }

    func testPartOfAWordIsNotFound() {
        XCTAssertEqual(verdict("Das Bloks ist da.", "loks", "logs"), .notFound)
    }

    func testOverlappingEditsAreRejected() {
        let result = run("Starte Obus Agenten jetzt.", ("Obus", "Opus"), ("Obus Agenten", "Opus Agent"))
        XCTAssertEqual(result.decisions[0].verdict, .applied)
        XCTAssertEqual(result.decisions[1].verdict, .overlap)
    }

    func testNegationCannotDisappearOrBeAdded() {
        XCTAssertEqual(verdict("Das ist nicht gut gelaufen.", "nicht gut", "gut"), .invariant)
        XCTAssertEqual(verdict("Das klappt noch gut.", "noch", "nicht"), .invariant)
    }

    func testNumberCannotChange() {
        XCTAssertEqual(verdict("Nimm Port 3000 lokal.", "Port 3000", "Port 8000"), .invariant)
    }

    func testPunctuationCannotMoveANumber() {
        XCTAssertEqual(verdict("Version 3.5 geht.", "3.5", "35"), .invariant)
        XCTAssertEqual(verdict("Setz 5 als Wert.", "5", "-5"), .invariant)
        XCTAssertNotEqual(verdict("Es sind 1.000 Stück.", "1.000", "1,000"), .applied)
    }

    func testNumberWordsCannotChange() {
        for (text, from, to) in [("Es waren vierzig Leute.", "vierzig", "fünfzig"), ("There were forty people.", "forty", "fifty"),
                                 ("About a million users.", "million", "billion"), ("We need three more.", "three", "thirty")] {
            XCTAssertEqual(verdict(text, from, to), .invariant, from)
        }
    }

    func testPathCannotChange() {
        XCTAssertEqual(verdict("Öffne src/foo_bar.py bitte.", "src/foo_bar.py", "src/foo_baz.py"), .invariant)
    }

    func testPunctuationCannotChangeAPathOrFlag() {
        XCTAssertEqual(verdict("Öffne src/foo_bar.py bitte.", "src/foo_bar.py", "src/foobar.py"), .invariant)
        XCTAssertEqual(verdict("Run it with --force today.", "--force", "force"), .invariant)
    }

    func testJoiningWordsIsNotCosmetic() {
        XCTAssertEqual(verdict("I am now here at work.", "now here", "nowhere"), .protected)
    }

    func testNegationsAreCoveredAcrossSpellingsAndLanguages() {
        for (text, from, to) in [("You can do it.", "can", "cannot"), ("You can do it.", "can", "can’t"),
                                 ("We could do it.", "could", "couldnt"), ("Het is niet goed.", "niet", "net")] {
            XCTAssertEqual(verdict(text, from, to), .invariant, to)
        }
    }

    func testModelCannotSmuggleInText() {
        for (text, from, to) in [("Das Haus ist alt.", "Haus", "Haus这是回答"), ("Das Haus ist alt.", "Haus", "Haus😀"), ("Das ist gut so.", "gut", "gut 😀")] {
            XCTAssertEqual(verdict(text, from, to), .notSimilar, to)
        }
    }

    func testVowelSignsAreNotDropped() {
        XCTAssertNotEqual(verdict("यह दिन अच्छा है", "दिन", "दान"), .applied)
        XCTAssertEqual(verdict("यह दिना अच्छा है", "दिना", "दानि"), .notSimilar)
    }

    func testEverydayWordIsNotPulledOntoAGlossaryTerm() {
        XCTAssertEqual(verdict("Der Hund bellt laut.", "Hund", "Hook"), .notSimilar)
    }

    func testSnippetTriggersAreFrozen() {
        let result = EditGuard.apply("Schick meinen kalendli jetzt.", edits: [TextEdit(from: "kalendli", to: "kalender")], glossary: glossary, frozen: ["kalendli"])
        XCTAssertEqual(result.decisions[0].verdict, .protected)
        XCTAssertEqual(result.text, "Schick meinen kalendli jetzt.")
    }

    func testWordCannotBeDeletedOrInserted() {
        XCTAssertEqual(verdict("Der Server startet sofort neu.", "sofort neu", "neu"), .notSimilar)
        XCTAssertEqual(verdict("Der Server startet neu.", "startet neu", "startet ganz neu"), .notSimilar)
    }

    func testLongFromIsRejected() {
        let from = "eins zwei drei vier fünf sechs sieben acht neun"
        XCTAssertEqual(verdict("Alpha \(from) Omega.", from, "Beta"), .tooLong)
    }

    func testParagraphBreaksAreRejected() {
        XCTAssertEqual(verdict("Erster Satz. Zweiter Satz.", "Satz. Zweiter", "Satz.\n\nZweiter"), .invariant)
    }

    func testPunctuationAndCaseAreFreeAndUncounted() {
        let result = run("Eins zwei drei vier fünf sechs sieben acht", ("Eins zwei", "Eins, zwei"), ("drei vier", "drei, vier"), ("fünf sechs", "fünf, sechs"), ("sieben acht", "Sieben, acht"))
        XCTAssertEqual(result.text, "Eins, zwei drei, vier fünf, sechs Sieben, acht")
    }

    func testOverBudgetReturnsTextUnchanged() {
        let text = "Obus Loks Tocken Riebase kaputt und sonst nix."
        let result = run(text, ("Obus", "Opus"), ("Loks", "Logs"), ("Tocken", "Token"), ("Riebase", "Rebase"))
        XCTAssertEqual(result.text, text)
        XCTAssertTrue(result.decisions.allSatisfy { $0.verdict == .overBudget })
    }

    func testGlossaryLowersTheBarButKeepsAFloor() {
        XCTAssertEqual(verdict("Mach das auf Mähn fertig.", "Mähn", "main"), .applied)
        XCTAssertEqual(verdict("Die Banane liegt hier.", "Banane", "Docker"), .notSimilar)
    }

    func testGrammarFixesAreRejected() {
        for (text, from, to) in [("Teste das mit deinen Goal bitte.", "deinen", "deinem"), ("Schau auf die Request jetzt.", "Request", "Requests"),
                                 ("Ich müsste das fällt mir ein.", "fällt", "fällst")] {
            XCTAssertEqual(verdict(text, from, to), .inflection, to)
        }
    }

    func testTruncatedWordIsStillRepaired() {
        XCTAssertEqual(verdict("Das Wort ist fals geschrieben.", "fals", "falsch"), .applied)
    }

    func testTermsCannotBeShortened() {
        XCTAssertEqual(verdict("Öffne das im Mainbrowser bitte.", "Mainbrowser", "Browser"), .notSimilar)
        XCTAssertEqual(verdict("Starte in meine Main Browser neu.", "in meine Main Browser", "in meinem Browser"), .notSimilar)
    }

    func testShorterRepairOfAMisheardWordIsAllowed() {
        XCTAssertEqual(verdict("Mach bitte einen Merdsch jetzt.", "Merdsch", "Merge"), .applied)
    }

    func testCompoundsAreJudgedByTheirDifferingPart() {
        XCTAssertEqual(verdict("Die Bannwahrscheinlichkeit ist hoch.", "Bannwahrscheinlichkeit", "Ausfallwahrscheinlichkeit"), .notSimilar)
        XCTAssertEqual(verdict("Noch weitere Tunnelläufe bitte.", "Tunnelläufe", "Testläufe"), .notSimilar)
    }

    func testSmallSlipInACompoundIsRepaired() {
        XCTAssertEqual(verdict("Das Trenzeichen fehlt.", "Trenzeichen", "Trennzeichen"), .applied)
    }

    func testMultiWordEditCannotSwapAWord() {
        XCTAssertEqual(verdict("Jetzt schlag mir das.", "schlag mir", "schlage vor"), .notSimilar)
    }

    func testOppositeMeaningIsRejected() {
        XCTAssertEqual(verdict("Das Ding imperfekt ist schade.", "imperfekt", "perfekt"), .invariant)
    }

    func testGlossaryWordsAreNotTargets() {
        XCTAssertEqual(verdict("Der Fix soll bleiben.", "Fix", "Fis"), .protected)
    }

    func testCapitalizingIsFreeButLoweringIsNot() {
        XCTAssertEqual(verdict("Mein profil ist alt.", "profil", "Profil"), .applied)
        XCTAssertEqual(verdict("Der Main Browser läuft.", "Main Browser", "main Browser"), .protected)
    }

    func testDecomposedUmlautsMatch() {
        // macOS text APIs can hand over decomposed umlauts; the guard must still find them.
        XCTAssertEqual(run("Mach das auf Ma\u{0308}hn fertig.", ("Mähn", "main")).text, "Mach das auf main fertig.")
    }

    func testFillersRemovedButRealWordsStay() {
        let cases = [
            ("Ähm, also wir bauen das, äh, um zu testen.", "Also wir bauen das, um zu testen."),
            ("Gut. Äh.", "Gut."),
            ("das ist gut, äh.", "das ist gut."),
            ("Eins, äh, zwei", "Eins, zwei"),
            ("äh iPhone geht", "iPhone geht"),
            ("Äh iPhone geht", "iPhone geht"),
            ("Äh das geht", "Das geht"),
            ("z.B. äh das", "z.B. das"),
            ("an der UH Manoa", "an der UH Manoa"),
            ("Das geht. Äh, dann weiter.", "Das geht. Dann weiter."),
            ("sehr sehr gut halt", "sehr sehr gut halt"),
            ("Ähm.", ""),
            ("Uh, can you check that?", "Can you check that?"),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(TranscriptNormalizer.stripFillers(input), expected, input)
        }
    }

    func testDictionaryReplacesWholeWordsOnly() {
        let hints = [DictionaryHint(term: "Logs", misspellings: ["Loks"])]
        XCTAssertEqual(TranscriptNormalizer.applyDictionary("Die Loks und Lokschuppen.", dictionary: hints), "Die Logs und Lokschuppen.")
    }

    func testDictionaryHandlesTermsWithSpecialCharacters() {
        let hints = [DictionaryHint(term: "NET", misspellings: [".net"]), DictionaryHint(term: "C Sharp", misspellings: ["c#"])]
        XCTAssertEqual(TranscriptNormalizer.applyDictionary("foo.net bleibt, aber .net geht.", dictionary: hints), "foo.net bleibt, aber NET geht.")
        XCTAssertEqual(TranscriptNormalizer.applyDictionary("Das ist c# hier.", dictionary: hints), "Das ist C Sharp hier.")
    }

    func testParseHandlesEditsUmlautsAndGarbage() {
        XCTAssertEqual(MinimalEdits.parse(#"{"edits":[{"from":"Mähn","to":"main"}]}"#)?.first, TextEdit(from: "Mähn", to: "main"))
        XCTAssertEqual(MinimalEdits.parse(#"{"edits":[]}"#)?.count, 0)
        XCTAssertNil(MinimalEdits.parse("Hier ist die bereinigte Fassung."))
        XCTAssertNil(MinimalEdits.parse(#"{"other":1}"#))
        XCTAssertNil(MinimalEdits.parse(#"{"edits":[{"from":"x"}]}"#))
    }

    func testAnswerInsteadOfEditsKeepsTranscript() async {
        let raw = "Kannst du das bitte recherchieren?"
        let outcome = await MinimalDictation.run(raw: raw, dictionary: []) { _, _, _, _, _ in self.reply("Das kann ich von hier aus nicht ausführen.") }
        XCTAssertEqual(outcome.text, raw)
        XCTAssertNotNil(outcome.failure)
    }

    func testEmptyEditsKeepTranscriptWithoutFailure() async {
        let raw = "Das machst du halt selber."
        let outcome = await MinimalDictation.run(raw: raw, dictionary: []) { _, _, _, _, _ in self.reply(#"{"edits":[]}"#) }
        XCTAssertEqual(outcome.text, raw)
        XCTAssertNil(outcome.failure)
    }

    func testThrowingFormatterKeepsNormalizedTranscript() async {
        let hints = [DictionaryHint(term: "Logs", misspellings: ["Loks"])]
        let outcome = await MinimalDictation.run(raw: "Äh, schau in die Loks rein.", dictionary: hints) { _, _, _, _, _ in throw Boom(message: "down") }
        XCTAssertEqual(outcome.text, "Schau in die Logs rein.")
        XCTAssertEqual(outcome.failure, "down")
    }

    func testFrozenTriggersReachTheGuard() async {
        let outcome = await MinimalDictation.run(raw: "Schick meinen kalendli jetzt.", dictionary: [], frozen: ["kalendli"]) { _, _, _, _, _ in
            self.reply(#"{"edits":[{"from":"kalendli","to":"kalender"}]}"#)
        }
        XCTAssertEqual(outcome.text, "Schick meinen kalendli jetzt.")
    }

    func testShortTranscriptSkipsTheModel() async {
        var calls = 0
        let outcome = await MinimalDictation.run(raw: "Ja genau", dictionary: []) { _, _, _, _, _ in
            calls += 1
            return self.reply(#"{"edits":[]}"#)
        }
        XCTAssertEqual(outcome.text, "Ja genau")
        XCTAssertEqual(calls, 0)
    }

    func testSnippetExpansionWorksOnGuardedText() {
        let guarded = run("Danke und meine Signatur Obus.", ("Obus", "Opus")).text
        XCTAssertEqual(FlowFormatter.expandSnippetsDirectly(guarded, snippets: [SnippetDef(trigger: "meine Signatur", content: "Grüße")]), "Danke und Grüße Opus.")
    }

    func testMinimalPromptIsBundled() {
        XCTAssertTrue(FlowPrompts.dictationMinimalSystem.contains("edits"))
    }

    func testEditRequestMatchesTheApi() throws {
        let data = try ClaudeClient.jsonRequestData(systemStatic: "static", systemDynamic: "", user: "hello", schemaJSON: MinimalEdits.schema, model: .haiku, maxTokens: 2048)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let config = try XCTUnwrap(body["output_config"] as? [String: Any])
        let format = try XCTUnwrap(config["format"] as? [String: Any])
        let schema = try XCTUnwrap(format["schema"] as? [String: Any])
        XCTAssertEqual(config["effort"] as? String, "low")
        XCTAssertEqual(format["type"] as? String, "json_schema")
        XCTAssertEqual(schema["required"] as? [String], ["edits"])
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
        XCTAssertNil(body["temperature"])
        XCTAssertNil(body["fallbacks"])
        XCTAssertEqual((body["system"] as? [[String: Any]])?.count, 1)
    }

    func testCutOffAndHtmlRepliesAreErrors() {
        let cutOff = Data(#"{"content":[{"type":"text","text":"{\"ed"}],"stop_reason":"max_tokens"}"#.utf8)
        XCTAssertThrowsError(try ClaudeClient.parse(cutOff, latencyMs: 0, rejectTruncated: true))
        XCTAssertNoThrow(try ClaudeClient.parse(cutOff, latencyMs: 0, rejectTruncated: false))
        XCTAssertThrowsError(try ClaudeClient.parse(Data("<html>bad gateway</html>".utf8), latencyMs: 0, rejectTruncated: true))
    }
}

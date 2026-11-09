using OpenWispr.Core;
using Xunit;

public class MinimalDictationTests
{
    private static readonly IReadOnlySet<string> Glossary = CodingGlossary.With([]);

    private static GuardResult Guard(string text, params (string From, string To)[] edits) =>
        EditGuard.Apply(text, edits.Select(e => new TextEdit(e.From, e.To)).ToList(), Glossary);

    private static EditVerdict Verdict(string text, string from, string to) => Guard(text, (from, to)).Decisions[0].Verdict;

    [Fact]
    public void RepairsMisheardWord()
    {
        var result = Guard("Starte das mit Obus und schau nach.", ("Obus", "Opus"));
        Assert.Equal("Starte das mit Opus und schau nach.", result.Text);
        Assert.Equal(EditVerdict.Applied, result.Decisions[0].Verdict);
    }

    [Fact]
    public void AcceptsPhraseRepairWithSharedWord()
    {
        Assert.Equal("Test alles voll autonom bitte.", Guard("Test alles voll aus Norm bitte.", ("voll aus Norm", "voll autonom")).Text);
    }

    [Theory]
    [InlineData("Gib mir Access auf alles.", "Access", "Zugriff")]
    [InlineData("Plan von Scratch neu ansehen.", "Scratch", "Grund auf")]
    public void RejectsTranslations(string text, string from, string to)
    {
        var result = Guard(text, (from, to));
        Assert.Equal(EditVerdict.NotSimilar, result.Decisions[0].Verdict);
        Assert.Equal(text, result.Text);
    }

    [Theory]
    [InlineData("selber", "selbst")]
    [InlineData("halt", "bitte")]
    public void ProtectedWordsStay(string from, string to)
    {
        var text = $"Das machst du {from} jetzt.";
        Assert.Equal(EditVerdict.Protected, Verdict(text, from, to));
        Assert.Equal(text, Guard(text, (from, to)).Text);
    }

    [Fact]
    public void AmbiguousFromIsRejectedAndAnchorResolvesIt()
    {
        const string text = "Die Loks sind weg und die Loks kommen.";
        Assert.Equal(EditVerdict.Ambiguous, Verdict(text, "Loks", "Logs"));
        Assert.Equal("Die Loks sind weg und die Logs kommen.", Guard(text, ("die Loks kommen", "die Logs kommen")).Text);
    }

    [Fact]
    public void PartOfAWordIsNotFound()
    {
        Assert.Equal(EditVerdict.NotFound, Verdict("Das Bloks ist da.", "loks", "logs"));
    }

    [Fact]
    public void OverlappingEditsAreRejected()
    {
        var result = Guard("Starte Obus Agenten jetzt.", ("Obus", "Opus"), ("Obus Agenten", "Opus Agent"));
        Assert.Equal(EditVerdict.Applied, result.Decisions[0].Verdict);
        Assert.Equal(EditVerdict.Overlap, result.Decisions[1].Verdict);
    }

    [Fact]
    public void NegationCannotDisappear()
    {
        Assert.Equal(EditVerdict.Invariant, Verdict("Das ist nicht gut gelaufen.", "nicht gut", "gut"));
    }

    [Fact]
    public void NegationCannotBeAdded()
    {
        Assert.Equal(EditVerdict.Invariant, Verdict("Das klappt noch gut.", "noch", "nicht"));
    }

    [Fact]
    public void NumberCannotChange()
    {
        Assert.Equal(EditVerdict.Invariant, Verdict("Nimm Port 3000 lokal.", "Port 3000", "Port 8000"));
    }

    [Theory]
    [InlineData("Version 3.5 geht.", "3.5", "35")]
    [InlineData("Setz 5 als Wert.", "5", "-5")]
    public void PunctuationCannotMoveANumber(string text, string from, string to)
    {
        Assert.Equal(EditVerdict.Invariant, Verdict(text, from, to));
    }

    [Fact]
    public void NumberSeparatorsAreNotCosmetic()
    {
        Assert.NotEqual(EditVerdict.Applied, Verdict("Es sind 1.000 Stück.", "1.000", "1,000"));
    }

    [Theory]
    [InlineData("Es waren vierzig Leute.", "vierzig", "fünfzig")]
    [InlineData("There were forty people.", "forty", "fifty")]
    [InlineData("About a million users.", "million", "billion")]
    [InlineData("We need three more.", "three", "thirty")]
    public void NumberWordsCannotChange(string text, string from, string to)
    {
        Assert.Equal(EditVerdict.Invariant, Verdict(text, from, to));
    }

    [Fact]
    public void PathCannotChange()
    {
        Assert.Equal(EditVerdict.Invariant, Verdict("Öffne src/foo_bar.py bitte.", "src/foo_bar.py", "src/foo_baz.py"));
    }

    [Theory]
    [InlineData("Öffne src/foo_bar.py bitte.", "src/foo_bar.py", "src/foobar.py")]
    [InlineData("Run it with --force today.", "--force", "force")]
    public void PunctuationCannotChangeAPathOrFlag(string text, string from, string to)
    {
        Assert.Equal(EditVerdict.Invariant, Verdict(text, from, to));
    }

    [Fact]
    public void JoiningWordsIsNotCosmetic()
    {
        Assert.Equal(EditVerdict.Protected, Verdict("I am now here at work.", "now here", "nowhere"));
    }

    [Theory]
    [InlineData("You can do it.", "can", "cannot")]
    [InlineData("You can do it.", "can", "can’t")]
    [InlineData("We could do it.", "could", "couldnt")]
    [InlineData("Het is niet goed.", "niet", "net")]
    public void NegationsAreCoveredAcrossSpellingsAndLanguages(string text, string from, string to)
    {
        Assert.Equal(EditVerdict.Invariant, Verdict(text, from, to));
    }

    [Theory]
    [InlineData("Das Haus ist alt.", "Haus", "Haus这是回答")]
    [InlineData("Das Haus ist alt.", "Haus", "Haus😀")]
    [InlineData("Das ist gut so.", "gut", "gut 😀")]
    public void ModelCannotSmuggleInText(string text, string from, string to)
    {
        Assert.Equal(EditVerdict.NotSimilar, Verdict(text, from, to));
    }

    [Fact]
    public void VowelSignsAreNotDropped()
    {
        Assert.NotEqual(EditVerdict.Applied, Verdict("यह दिन अच्छा है", "दिन", "दान"));
        Assert.Equal(EditVerdict.NotSimilar, Verdict("यह दिना अच्छा है", "दिना", "दानि")); // same characters, other vowels: not cosmetic
    }

    [Fact]
    public void EverydayWordIsNotPulledOntoAGlossaryTerm()
    {
        Assert.Equal(EditVerdict.NotSimilar, Verdict("Der Hund bellt laut.", "Hund", "Hook"));
    }

    [Fact]
    public void SnippetTriggersAreFrozen()
    {
        var edits = new[] { new TextEdit("kalendli", "kalender") };
        var result = EditGuard.Apply("Schick meinen kalendli jetzt.", edits, Glossary, ["kalendli"]);
        Assert.Equal(EditVerdict.Protected, result.Decisions[0].Verdict);
        Assert.Equal("Schick meinen kalendli jetzt.", result.Text);
    }

    [Fact]
    public void WordCannotBeDeletedOrInserted()
    {
        Assert.Equal(EditVerdict.NotSimilar, Verdict("Der Server startet sofort neu.", "sofort neu", "neu"));
        Assert.Equal(EditVerdict.NotSimilar, Verdict("Der Server startet neu.", "startet neu", "startet ganz neu"));
    }

    [Fact]
    public void LongFromIsRejected()
    {
        const string from = "eins zwei drei vier fünf sechs sieben acht neun";
        Assert.Equal(EditVerdict.TooLong, Verdict($"Alpha {from} Omega.", from, "Beta"));
    }

    [Fact]
    public void ParagraphBreaksAreRejected()
    {
        Assert.Equal(EditVerdict.Invariant, Verdict("Erster Satz. Zweiter Satz.", "Satz. Zweiter", "Satz.\n\nZweiter"));
    }

    [Fact]
    public void PunctuationAndCaseAreFreeAndUncounted()
    {
        const string text = "Eins zwei drei vier fünf sechs sieben acht";
        var result = Guard(text, ("Eins zwei", "Eins, zwei"), ("drei vier", "drei, vier"), ("fünf sechs", "fünf, sechs"), ("sieben acht", "Sieben, acht"));
        Assert.Equal("Eins, zwei drei, vier fünf, sechs Sieben, acht", result.Text);
    }

    [Fact]
    public void OverBudgetReturnsTextUnchanged()
    {
        const string text = "Obus Loks Tocken Riebase kaputt und sonst nix.";
        var result = Guard(text, ("Obus", "Opus"), ("Loks", "Logs"), ("Tocken", "Token"), ("Riebase", "Rebase"));
        Assert.Equal(text, result.Text);
        Assert.All(result.Decisions, d => Assert.Equal(EditVerdict.OverBudget, d.Verdict));
    }

    [Fact]
    public void GlossaryLowersTheBarButKeepsAFloor()
    {
        Assert.Equal(EditVerdict.Applied, Verdict("Mach das auf Mähn fertig.", "Mähn", "main"));
        Assert.Equal(EditVerdict.NotSimilar, Verdict("Die Banane liegt hier.", "Banane", "Docker"));
    }

    [Theory]
    [InlineData("Teste das mit deinen Goal bitte.", "deinen", "deinem")]
    [InlineData("Schau auf die Request jetzt.", "Request", "Requests")]
    [InlineData("Ich müsste das fällt mir ein.", "fällt", "fällst")]
    public void GrammarFixesAreRejected(string text, string from, string to)
    {
        Assert.Equal(EditVerdict.Inflection, Verdict(text, from, to));
    }

    [Fact]
    public void TruncatedWordIsStillRepaired()
    {
        Assert.Equal(EditVerdict.Applied, Verdict("Das Wort ist fals geschrieben.", "fals", "falsch"));
    }

    [Theory]
    [InlineData("Öffne das im Mainbrowser bitte.", "Mainbrowser", "Browser")]
    [InlineData("Starte in meine Main Browser neu.", "in meine Main Browser", "in meinem Browser")]
    public void TermsCannotBeShortened(string text, string from, string to)
    {
        Assert.Equal(EditVerdict.NotSimilar, Verdict(text, from, to));
    }

    [Fact]
    public void ShorterRepairOfAMisheardWordIsAllowed()
    {
        Assert.Equal(EditVerdict.Applied, Verdict("Mach bitte einen Merdsch jetzt.", "Merdsch", "Merge"));
    }

    [Theory]
    [InlineData("Die Bannwahrscheinlichkeit ist hoch.", "Bannwahrscheinlichkeit", "Ausfallwahrscheinlichkeit")]
    [InlineData("Noch weitere Tunnelläufe bitte.", "Tunnelläufe", "Testläufe")]
    public void CompoundsAreJudgedByTheirDifferingPart(string text, string from, string to)
    {
        Assert.Equal(EditVerdict.NotSimilar, Verdict(text, from, to));
    }

    [Fact]
    public void SmallSlipInACompoundIsRepaired()
    {
        Assert.Equal(EditVerdict.Applied, Verdict("Das Trenzeichen fehlt.", "Trenzeichen", "Trennzeichen"));
    }

    [Fact]
    public void MultiWordEditCannotSwapAWord()
    {
        Assert.Equal(EditVerdict.NotSimilar, Verdict("Jetzt schlag mir das.", "schlag mir", "schlage vor"));
    }

    [Fact]
    public void OppositeMeaningIsRejected()
    {
        Assert.Equal(EditVerdict.Invariant, Verdict("Das Ding imperfekt ist schade.", "imperfekt", "perfekt"));
    }

    [Fact]
    public void GlossaryWordsAreNotTargets()
    {
        Assert.Equal(EditVerdict.Protected, Verdict("Der Fix soll bleiben.", "Fix", "Fis"));
    }

    [Fact]
    public void CapitalizingIsFreeButLoweringIsNot()
    {
        Assert.Equal(EditVerdict.Applied, Verdict("Mein profil ist alt.", "profil", "Profil"));
        Assert.Equal(EditVerdict.Protected, Verdict("Der Main Browser läuft.", "Main Browser", "main Browser"));
    }

    [Fact]
    public void FillersRemovedButRealWordsStay()
    {
        Assert.Equal("Also wir bauen das, um zu testen.", TranscriptNormalizer.StripFillers("Ähm, also wir bauen das, äh, um zu testen."));
        Assert.Equal("Gut.", TranscriptNormalizer.StripFillers("Gut. Äh."));
        Assert.Equal("das ist gut.", TranscriptNormalizer.StripFillers("das ist gut, äh."));
        Assert.Equal("Eins, zwei", TranscriptNormalizer.StripFillers("Eins, äh, zwei"));
        Assert.Equal("iPhone geht", TranscriptNormalizer.StripFillers("äh iPhone geht"));
        Assert.Equal("iPhone geht", TranscriptNormalizer.StripFillers("Äh iPhone geht"));
        Assert.Equal("Das geht", TranscriptNormalizer.StripFillers("Äh das geht"));
        Assert.Equal("z.B. das", TranscriptNormalizer.StripFillers("z.B. äh das"));
        Assert.Equal("an der UH Manoa", TranscriptNormalizer.StripFillers("an der UH Manoa"));
        Assert.Equal("Das geht. Dann weiter.", TranscriptNormalizer.StripFillers("Das geht. Äh, dann weiter."));
        Assert.Equal("sehr sehr gut halt", TranscriptNormalizer.StripFillers("sehr sehr gut halt"));
        Assert.Equal("", TranscriptNormalizer.StripFillers("Ähm."));
        Assert.Equal("Can you check that?", TranscriptNormalizer.StripFillers("Uh, can you check that?"));
    }

    [Fact]
    public void DictionaryReplacesWholeWordsOnly()
    {
        var hints = new[] { new DictionaryHint("Logs", ["Loks"]) };
        Assert.Equal("Die Logs und Lokschuppen.", TranscriptNormalizer.ApplyDictionary("Die Loks und Lokschuppen.", hints));
    }

    [Fact]
    public void DictionaryHandlesTermsWithSpecialCharacters()
    {
        var hints = new[] { new DictionaryHint("NET", [".net"]), new DictionaryHint("C Sharp", ["c#"]) };
        Assert.Equal("foo.net bleibt, aber NET geht.", TranscriptNormalizer.ApplyDictionary("foo.net bleibt, aber .net geht.", hints));
        Assert.Equal("Das ist C Sharp hier.", TranscriptNormalizer.ApplyDictionary("Das ist c# hier.", hints));
    }

    [Fact]
    public void ParseHandlesEditsUmlautsAndGarbage()
    {
        Assert.Equal(new TextEdit("Mähn", "main"), MinimalEdits.Parse("""{"edits":[{"from":"Mähn","to":"main"}]}""")![0]);
        Assert.Empty(MinimalEdits.Parse("""{"edits":[]}""")!);
        Assert.Null(MinimalEdits.Parse("Hier ist die bereinigte Fassung."));
        Assert.Null(MinimalEdits.Parse("""{"other":1}"""));
        Assert.Null(MinimalEdits.Parse("""{"edits":[{"from":"x"}]}"""));
    }

    private sealed class FakeFormatter(Func<string> reply) : IEditFormatter
    {
        public int Calls { get; private set; }
        public Task<FormatResult> CompleteJsonAsync(string s, string d, string u, string schema, int max, CancellationToken ct)
        {
            Calls++;
            return Task.FromResult(new FormatResult(reply(), "fake", 0, 0, 0, 0));
        }
    }

    [Fact]
    public async Task AnswerInsteadOfEditsKeepsTranscript()
    {
        const string raw = "Kannst du das bitte recherchieren?";
        var outcome = await MinimalDictation.RunAsync(new FakeFormatter(() => "Das kann ich von hier aus nicht ausführen."), raw, [], default);
        Assert.Equal(raw, outcome.Text);
        Assert.NotNull(outcome.Failure);
    }

    [Fact]
    public async Task EmptyEditsKeepTranscriptWithoutFailure()
    {
        const string raw = "Das machst du halt selber.";
        var outcome = await MinimalDictation.RunAsync(new FakeFormatter(() => """{"edits":[]}"""), raw, [], default);
        Assert.Equal(raw, outcome.Text);
        Assert.Null(outcome.Failure);
    }

    [Fact]
    public async Task ThrowingFormatterKeepsNormalizedTranscript()
    {
        var hints = new[] { new DictionaryHint("Logs", ["Loks"]) };
        var outcome = await MinimalDictation.RunAsync(new FakeFormatter(() => throw new FormatterException("down")), "Äh, schau in die Loks rein.", hints, default);
        Assert.Equal("Schau in die Logs rein.", outcome.Text);
        Assert.Equal("down", outcome.Failure);
    }

    [Fact]
    public async Task UnexpectedExceptionStillKeepsNormalizedTranscript()
    {
        var outcome = await MinimalDictation.RunAsync(new FakeFormatter(() => throw new System.Text.Json.JsonException("html page")), "Schau dir das bitte an.", [], default);
        Assert.Equal("Schau dir das bitte an.", outcome.Text);
        Assert.NotNull(outcome.Failure);
    }

    [Fact]
    public async Task FrozenTriggersReachTheGuard()
    {
        var fake = new FakeFormatter(() => """{"edits":[{"from":"kalendli","to":"kalender"}]}""");
        var outcome = await MinimalDictation.RunAsync(fake, "Schick meinen kalendli jetzt.", [], default, ["kalendli"]);
        Assert.Equal("Schick meinen kalendli jetzt.", outcome.Text);
    }

    [Fact]
    public async Task ShortTranscriptSkipsTheModel()
    {
        var fake = new FakeFormatter(() => """{"edits":[]}""");
        var outcome = await MinimalDictation.RunAsync(fake, "Ja genau", [], default);
        Assert.Equal("Ja genau", outcome.Text);
        Assert.Equal(0, fake.Calls);
    }

    [Fact]
    public void SnippetExpansionWorksOnGuardedText()
    {
        var guarded = Guard("Danke und meine Signatur Obus.", ("Obus", "Opus")).Text;
        Assert.Equal("Danke und Grüße Opus.", FlowFormatter.ExpandSnippetsDirectly(guarded, [new SnippetDef("meine Signatur", "Grüße")]));
    }
}

// notchcast-sources: Tinycast/Features/Todo/Model/*.swift
import Foundation

@main
@MainActor
struct TodoQuickAddTests {
    static var checks = 0
    static var failures = 0
    static var cases = 0
    static let projects = ["Home", "Home Office", "Home Office Renovation", "Work", "Café", "🏡 Dom"]
    static let sections = ["Inbox", "This", "This Week", "Upcoming"]
    static let labels = ["errand", "deep", "deep work", "shopping", "ważne", "👨‍👩‍👧‍👦 rodzina"]

    struct ParseCase {
        let name: String
        let input: String
        let title: String
        var project: String?
        var section: String?
        var labels: [String] = []
        var priority: Int = 1
        var date: String?
        var tokens: [TodoQuickAddToken.Kind: String] = [:]
    }

    static func main() {
        parseCases()
        reversionCases()
        pasteCases()
        dateBoundaryCases()
        unicodeCases()
        expect(cases >= 40, "at least 40 behavioral cases")
        print("Todo quick add: \(cases) cases, \(checks - failures)/\(checks) checks passed")
        if failures > 0 { exit(1) }
    }

    static func parseCases() {
        let examples: [ParseCase] = [
            .init(name: "empty", input: "", title: ""),
            .init(name: "blank", input: " \t\n ", title: ""),
            .init(name: "plain", input: "Buy milk", title: "Buy milk"),
            .init(name: "whitespace", input: " \tBuy  milk\n and\u{00A0}bread ", title: "Buy milk and bread"),
            .init(name: "project", input: "Buy #Home milk", title: "Buy milk", project: "Home", tokens: [.project: "#Home"]),
            .init(name: "section", input: "/Inbox Buy milk", title: "Buy milk", section: "Inbox", tokens: [.section: "/Inbox"]),
            .init(name: "label", input: "Buy milk @errand", title: "Buy milk", labels: ["errand"], tokens: [.label: "@errand"]),
            .init(
                name: "catalogue example", input: "Buy milk tomorrow 9am #Home @errand p1", title: "Buy milk",
                project: "Home", labels: ["errand"], priority: 4, date: "tomorrow 9am",
                tokens: [.date: "tomorrow 9am", .project: "#Home", .label: "@errand", .priority: "p1"]),
            .init(
                name: "all five types", input: "#Home Buy /Inbox milk @errand tomorrow p2", title: "Buy milk",
                project: "Home", section: "Inbox", labels: ["errand"], priority: 3, date: "tomorrow",
                tokens: [.project: "#Home", .section: "/Inbox", .label: "@errand", .date: "tomorrow", .priority: "p2"]),
            .init(
                name: "rightmost project", input: "Buy #Home #Work", title: "Buy #Home", project: "Work",
                tokens: [.project: "#Work"]),
            .init(
                name: "rightmost section", input: "/Inbox Buy /Upcoming", title: "/Inbox Buy", section: "Upcoming",
                tokens: [.section: "/Upcoming"]),
            .init(
                name: "rightmost label", input: "Buy @errand @shopping", title: "Buy @errand", labels: ["shopping"],
                tokens: [.label: "@shopping"]),
            .init(
                name: "rightmost priority", input: "p1 Buy p3", title: "p1 Buy", priority: 2, tokens: [.priority: "p3"]),
            .init(
                name: "rightmost date", input: "tomorrow Buy next week", title: "tomorrow Buy", date: "next week",
                tokens: [.date: "next week"]),
            .init(
                name: "repeated identical project", input: "#Home Buy #Home", title: "#Home Buy", project: "Home",
                tokens: [.project: "#Home"]),
            .init(
                name: "repeated identical date", input: "tomorrow Buy tomorrow", title: "tomorrow Buy", date: "tomorrow",
                tokens: [.date: "tomorrow"]),
            .init(name: "case project", input: "#hOmE task", title: "task", project: "Home", tokens: [.project: "#hOmE"]),
            .init(name: "case section", input: "task /iNbOx", title: "task", section: "Inbox", tokens: [.section: "/iNbOx"]),
            .init(name: "case label", input: "@ERRAND task", title: "task", labels: ["errand"], tokens: [.label: "@ERRAND"]),
            .init(
                name: "longest project", input: "Fix #Home Office Renovation today", title: "Fix today",
                project: "Home Office Renovation", tokens: [.project: "#Home Office Renovation"]),
            .init(
                name: "longest section", input: "Fix /This Week today", title: "Fix today", section: "This Week",
                tokens: [.section: "/This Week"]),
            .init(
                name: "longest label", input: "Fix @deep work today", title: "Fix today", labels: ["deep work"],
                tokens: [.label: "@deep work"]),
            .init(
                name: "shorter complete name", input: "Fix #Home OfficeX", title: "Fix OfficeX", project: "Home",
                tokens: [.project: "#Home"]),
            .init(name: "unknown project", input: "Fix #Unknown", title: "Fix #Unknown"),
            .init(name: "unknown section", input: "Fix /Unknown", title: "Fix /Unknown"),
            .init(name: "unknown label", input: "Fix @Unknown", title: "Fix @Unknown"),
            .init(name: "project prefix", input: "#Homework task", title: "#Homework task"),
            .init(name: "section prefix", input: "/Inboxx task", title: "/Inboxx task"),
            .init(name: "label prefix", input: "@errands task", title: "@errands task"),
            .init(name: "embedded markers", input: "foo#Home mail@errand path/Inbox", title: "foo#Home mail@errand path/Inbox"),
            .init(name: "no adjacent tokens", input: "#Home@errand p1p2", title: "#Home@errand p1p2"),
            .init(name: "punctuation boundary", input: "(#Home) @errand, p1.", title: "(#Home) @errand, p1."),
            .init(name: "p1 inversion", input: "task p1", title: "task", priority: 4, tokens: [.priority: "p1"]),
            .init(name: "p2 inversion", input: "task p2", title: "task", priority: 3, tokens: [.priority: "p2"]),
            .init(name: "p3 inversion", input: "task p3", title: "task", priority: 2, tokens: [.priority: "p3"]),
            .init(name: "p4 inversion", input: "task p4", title: "task", priority: 1, tokens: [.priority: "p4"]),
            .init(name: "uppercase priority", input: "task P1", title: "task", priority: 4, tokens: [.priority: "P1"]),
            .init(name: "invalid priority", input: "p0 p5 p10 ap1 p1x p١", title: "p0 p5 p10 ap1 p1x p١"),
            .init(name: "bare markers", input: "# / @ p", title: "# / @ p"),
            .init(name: "cut syntax", input: "automate: +Alice {Friday} 30m !9am", title: "automate: +Alice {Friday} 30m !9am"),
            .init(
                name: "quoted tokens", input: "Say \"#Home /Inbox @errand p1 tomorrow\"",
                title: "Say \"#Home /Inbox @errand p1 tomorrow\""),
            .init(
                name: "quotes then token", input: "\"#Home\" #Work", title: "\"#Home\"", project: "Work",
                tokens: [.project: "#Work"]),
            .init(name: "unclosed quote", input: "Say \"hello #Home tomorrow p1", title: "Say \"hello #Home tomorrow p1"),
            .init(name: "escaped quote inside", input: #"Say "hello \" #Home p1""#, title: #"Say "hello \" #Home p1""#),
            .init(name: "backslash project", input: "Buy \\#Home", title: "Buy \\#Home"),
            .init(name: "backslash section", input: #"Buy \/Inbox"#, title: #"Buy \/Inbox"#),
            .init(name: "backslash label", input: #"Buy \@errand"#, title: #"Buy \@errand"#),
            .init(name: "backslash priority", input: #"Buy \p1"#, title: #"Buy \p1"#),
            .init(name: "backslash date", input: #"Buy \tomorrow"#, title: #"Buy \tomorrow"#),
            .init(name: "quoted long name", input: "Buy \"#Home Office\"", title: "Buy \"#Home Office\""),
            .init(
                name: "apostrophe stays literal", input: "Don't forget #Home", title: "Don't forget", project: "Home",
                tokens: [.project: "#Home"]),
            .init(
                name: "Polish date", input: "Kup mleko w przyszły piątek #Home @ważne p1", title: "Kup mleko",
                project: "Home", labels: ["ważne"], priority: 4, date: "w przyszły piątek",
                tokens: [.date: "w przyszły piątek", .project: "#Home", .label: "@ważne", .priority: "p1"]),
            .init(
                name: "Polish time", input: "Zadzwoń jutro o 9", title: "Zadzwoń", date: "jutro o 9",
                tokens: [.date: "jutro o 9"]),
            .init(
                name: "emoji before tokens", input: "👩🏽‍💻 e\u{301} #Home @errand p2", title: "👩🏽‍💻 e\u{301}",
                project: "Home", labels: ["errand"], priority: 3,
                tokens: [.project: "#Home", .label: "@errand", .priority: "p2"]),
            .init(
                name: "emoji project", input: "Plan #🏡 Dom", title: "Plan", project: "🏡 Dom", tokens: [.project: "#🏡 Dom"]),
            .init(
                name: "emoji label", input: "Plan @👨‍👩‍👧‍👦 rodzina", title: "Plan", labels: ["👨‍👩‍👧‍👦 rodzina"],
                tokens: [.label: "@👨‍👩‍👧‍👦 rodzina"]),
            .init(
                name: "combining name", input: "Plan #Cafe\u{301}", title: "Plan", project: "Café",
                tokens: [.project: "#Cafe\u{301}"]),
            .init(
                name: "quoted emoji before date", input: "\"👩🏽‍💻 tomorrow\" Kup jutro", title: "\"👩🏽‍💻 tomorrow\" Kup",
                date: "jutro", tokens: [.date: "jutro"]),
            .init(
                name: "date inside unknown marker stays text", input: "#tomorrow task jutro", title: "#tomorrow task",
                date: "jutro", tokens: [.date: "jutro"]),
            .init(
                name: "date inside word stays text", input: "tomorrowland task jutro", title: "tomorrowland task",
                date: "jutro", tokens: [.date: "jutro"]),
            .init(name: "only token", input: "#Home", title: "", project: "Home", tokens: [.project: "#Home"])
        ]
        for example in examples {
            cases += 1
            let draft = parse(example.input)
            expect(draft.title == example.title, "\(example.name): title: \(draft.title)")
            expect(draft.project == example.project, "\(example.name): project")
            expect(draft.section == example.section, "\(example.name): section")
            expect(draft.labels == example.labels, "\(example.name): labels")
            expect(draft.priority == example.priority, "\(example.name): priority")
            expect(draft.date?.payload == example.date.map { "fake:\($0)" }, "\(example.name): date")
            expect(draft.tokens.count == example.tokens.count, "\(example.name): token count")
            expect(draft.tokens.map(\.range.location) == draft.tokens.map(\.range.location).sorted(), "\(example.name): order")
            for (kind, tokenText) in example.tokens {
                let expected = (example.input as NSString).range(of: tokenText, options: .backwards)
                let actual = draft.tokens.first { $0.kind == kind }?.range
                expect(actual == expected, "\(example.name): UTF-16 range for \(tokenText)")
                if kind == .date {
                    expect(draft.date?.range == expected, "\(example.name): date range")
                    expect(draft.date?.display == tokenText, "\(example.name): date display")
                }
            }
        }
    }

    static func reversionCases() {
        for (input, kind) in [
            ("Buy #Home", TodoQuickAddToken.Kind.project), ("Buy /Inbox", .section),
            ("Buy @errand", .label), ("Buy p1", .priority), ("Buy tomorrow 9am", .date)
        ] {
            cases += 1
            var parser = session(input)
            let result = parser.revert(tokenAt: input.utf16.count)
            expect(result.title == input && result.tokens.isEmpty, "revert \(kind) at trailing caret")
            expect(result.project == nil && result.section == nil && result.labels.isEmpty, "revert clears names")
            expect(result.priority == 1 && result.date == nil, "revert clears priority and date")
        }

        cases += 1
        var parser = session("#Home Buy #Work")
        let reverted = parser.revert(tokenAt: 12)
        expect(reverted.project == "Home" && reverted.title == "Buy #Work", "revert restores earlier project")
        expect(parser.parse(parser.text) == reverted, "reverted token stays literal on reparse")
        expect(parser.revert(tokenAt: -1) == reverted, "negative caret is a no-op")
        expect(parser.revert(tokenAt: 999) == reverted, "out of bounds caret is a no-op")
        expect(parser.revert(tokenAt: 7) == reverted, "plain text caret is a no-op")
        let both = parser.revert(tokenAt: 0)
        expect(both.title == "#Home Buy #Work" && both.tokens.isEmpty, "multiple reversions accumulate")

        cases += 1
        parser = session("Buy #Home")
        parser.revert(tokenAt: 9)
        expect(parser.parse("Buy #Home now").tokens.isEmpty, "append after reverted token preserves it")
        let moved = parser.parse("👩🏽‍💻 Buy #Home now p1")
        expect(moved.project == nil && moved.priority == 4 && moved.title == "👩🏽‍💻 Buy #Home now", "edit before shifts range")
        let shortened = parser.parse("Buy #Home now p1")
        expect(shortened.project == nil, "deletion before shifts range back")
        let edited = parser.parse("Buy #Work now p1")
        expect(edited.project == "Work", "editing inside a reverted token makes it eligible again")

        cases += 1
        parser = session("#Home #Home")
        parser.revert(tokenAt: 11)
        expect(parser.draft.title == "#Home" && parser.draft.tokens.first?.range.location == 0, "revert is range specific")

        cases += 1
        parser = session("#Home #Work")
        parser.revert(tokenAt: 11)
        parser.parse("#Home #Work now")
        expect(parser.draft.project == "Home", "editing keeps a reverted duplicate literal")
        let restored = parser.parse("#Home #Work")
        expect(restored.project == "Home", "deleting suffix keeps reverted duplicate literal")

        cases += 1
        parser = session("tomorrow Buy next week")
        let earlier = parser.revert(tokenAt: parser.text.utf16.count)
        expect(
            earlier.date?.payload == "fake:tomorrow" && earlier.title == "Buy next week",
            "date reversion reparses earlier dates")

        cases += 1
        parser = session("p1 Buy p4")
        let priority = parser.revert(tokenAt: parser.text.utf16.count)
        expect(priority.priority == 4 && priority.title == "Buy p4", "priority reversion restores inverted earlier value")

        cases += 1
        parser = TodoQuickAddParser(text: "Buy #next week", projects: ["next week"], dateParser: fakeDate)
        let literal = parser.revert(tokenAt: parser.text.utf16.count)
        expect(
            literal.project == nil && literal.date == nil && literal.title == "Buy #next week",
            "reverted name shields date phrase")

        cases += 1
        parser = session("Buy #Home")
        parser.revert(tokenAt: parser.text.utf16.count)
        expect(parser.parse("").tokens.isEmpty, "deleting a reverted token clears its range")
        expect(parser.parse("Buy #Home").project == "Home", "retyping a deleted token recognizes it again")
    }

    static func pasteCases() {
        cases += 1
        let paste = TodoQuickAddParser.splitPaste(
            "\n Buy milk #Home\r\n\t\rRead @deep work p1\nKup jutro o 9\u{2028}👩🏽‍💻 #Work\n",
            projects: projects, sections: sections, labels: labels, dateParser: fakeDate)
        expect(paste.count == 4 && paste.drafts.count == 4, "paste counts only non-empty lines")
        expect(paste.drafts.map(\.title) == ["Buy milk", "Read", "Kup", "👩🏽‍💻"], "paste preserves line order")
        expect(paste.drafts[0].project == "Home" && paste.drafts[3].project == "Work", "paste uses catalogues")
        expect(paste.drafts[1].priority == 4 && paste.drafts[1].labels == ["deep work"], "paste priority and label")
        expect(paste.drafts[2].date?.payload == "fake:jutro o 9", "paste uses injected dates")
        expect(paste.drafts[0].tokens.first?.range.location == 10, "paste ranges use the untrimmed individual line")
        expect(paste.drafts[3].tokens.first?.range.location == "👩🏽‍💻 ".utf16.count, "paste emoji range")

        cases += 1
        let blank = TodoQuickAddParser.splitPaste("\r\n \t\n\u{2029}")
        expect(blank.count == 0 && blank.drafts.isEmpty, "blank paste")
        cases += 1
        let single = session("").splitPaste("#Home")
        expect(single.count == 1 && single.drafts[0].title.isEmpty, "non-empty token-only line still counts")
        cases += 1
        let plain = TodoQuickAddParser.splitPaste("one\ntwo")
        expect(plain.count == 2 && plain.drafts.map(\.title) == ["one", "two"], "paste convenience defaults")
    }

    static func dateBoundaryCases() {
        for range in [
            NSRange(location: NSNotFound, length: 1), NSRange(location: -1, length: 1),
            NSRange(location: 0, length: 0), NSRange(location: 0, length: -1),
            NSRange(location: 0, length: Int.max), NSRange(location: 100, length: 1),
            NSRange(location: 1, length: 1), NSRange(location: 0, length: 2)
        ] {
            cases += 1
            let draft = TodoQuickAddParser.parse("👩🏽‍💻 task") { _ in
                TodoQuickAddDate(range: range, display: "fake", payload: "invalid")
            }
            expect(draft.title == "👩🏽‍💻 task" && draft.date == nil, "invalid callback range \(range) stays text")
        }

        cases += 1
        let overlap = TodoQuickAddParser.parse("#Home task", projects: ["Home"]) { _ in
            TodoQuickAddDate(range: NSRange(location: 0, length: 5), display: "fake", payload: "overlap")
        }
        expect(overlap.project == "Home" && overlap.date == nil && overlap.title == "task", "date cannot consume a name token")

        cases += 1
        let repeated = TodoQuickAddParser.parse("tomorrow task") { _ in
            TodoQuickAddDate(range: NSRange(location: 0, length: 8), display: "tomorrow", payload: "repeat")
        }
        expect(repeated.date?.payload == "repeat" && repeated.title == "task", "repeated callback range terminates")

        cases += 1
        let reverse = TodoQuickAddParser.parse("tomorrow task jutro") { text in
            if let range = text.range(of: "jutro") {
                return TodoQuickAddDate(range: NSRange(range, in: text), display: "jutro", payload: "last")
            }
            return fakeDate(text)
        }
        expect(
            reverse.date?.payload == "last" && reverse.title == "tomorrow task",
            "rightmost date wins regardless of callback order")

        cases += 1
        let namedDate = TodoQuickAddParser.parse(
            "Buy #tomorrow @next week tomorrow", projects: ["tomorrow"], labels: ["next week"],
            dateParser: fakeDate)
        expect(namedDate.project == "tomorrow" && namedDate.labels == ["next week"], "names shield date-like contents")
        expect(namedDate.date?.payload == "fake:tomorrow" && namedDate.title == "Buy", "date still matches after names")

        cases += 1
        let noNames = TodoQuickAddParser.parse("#Home /Inbox @errand p1", dateParser: { _ in nil })
        expect(noNames.title == "#Home /Inbox @errand" && noNames.priority == 4, "empty catalogues never create names")
    }

    static func unicodeCases() {
        cases += 1
        let input = "👩🏽‍💻 e\u{301} #🏡 Dom @👨‍👩‍👧‍👦 rodzina jutro p1"
        let draft = parse(input)
        for token in draft.tokens {
            guard let range = Range(token.range, in: input) else {
                expect(false, "Unicode token converts to String.Index range")
                continue
            }
            expect(input.indices.contains(range.lowerBound), "Unicode token starts on a character boundary")
            expect(
                range.upperBound == input.endIndex || input.indices.contains(range.upperBound),
                "Unicode token ends on boundary")
        }
        var parser = session(input)
        let offset = (input as NSString).range(of: "@👨‍👩‍👧‍👦 rodzina").location
        let result = parser.revert(tokenAt: offset + 3)
        expect(result.labels.isEmpty && result.title == "👩🏽‍💻 e\u{301} @👨‍👩‍👧‍👦 rodzina", "UTF-16 caret inside emoji token reverts it")

        cases += 1
        parser = session("Cafe\u{301} #Home")
        parser.revert(tokenAt: parser.text.utf16.count)
        expect(parser.parse("Café #Home").project == nil, "normalization before token remaps UTF-16 offsets")
        expect(parser.parse("Café #Home p1").title == "Café #Home", "normalized reverted range stays valid")

        cases += 1
        let splitCharacter = TodoQuickAddParser.parse("e\u{301} task") { _ in
            TodoQuickAddDate(range: NSRange(location: 0, length: 1), display: "e", payload: "split")
        }
        expect(
            splitCharacter.date == nil && splitCharacter.title == "e\u{301} task",
            "callback cannot split a combining character")
    }

    static func parse(_ text: String) -> TodoQuickAddDraft {
        TodoQuickAddParser.parse(text, projects: projects, sections: sections, labels: labels, dateParser: fakeDate)
    }

    static func session(_ text: String) -> TodoQuickAddParser {
        TodoQuickAddParser(text: text, projects: projects, sections: sections, labels: labels, dateParser: fakeDate)
    }

    nonisolated static func fakeDate(_ text: String) -> TodoQuickAddDate? {
        let phrases = ["tomorrow 9am", "tomorrow", "next week", "w przyszły piątek", "jutro o 9", "jutro", "dziś"]
        return phrases.compactMap { phrase -> TodoQuickAddDate? in
            guard let range = text.range(of: phrase, options: .caseInsensitive) else { return nil }
            return TodoQuickAddDate(range: NSRange(range, in: text), display: String(text[range]), payload: "fake:\(phrase)")
        }.sorted {
            if $0.range.location != $1.range.location { return $0.range.location < $1.range.location }
            return $0.range.length > $1.range.length
        }.first
    }

    static func expect(_ condition: Bool, _ message: String) {
        checks += 1
        if !condition {
            failures += 1
            print("FAIL: \(message)")
        }
    }
}

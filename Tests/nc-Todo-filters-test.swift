// notchcast-sources: Tinycast/Features/Todo/Model/*.swift
import Foundation

@main
@MainActor
struct TodoFilterTests {
    struct Subject: TodoFilterSubject, Equatable {
        var title: String
        var projectName: String?
        var projectPath: [String] = []
        var sectionName: String?
        var labels: [String] = []
        var priority = 1
        var dueDate: Date?
        var hasTime = false
        var isRecurring = false
        var isSubtask = false
        var isCompleted = false
    }

    static var passed = 0
    static var failed = 0

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        guard let zone = TimeZone(identifier: "Europe/Warsaw") else { fatalError("Missing fixture time zone") }
        calendar.timeZone = zone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    static func date(_ month: Int = 3, _ day: Int = 10, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        guard let date = calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))
        else { fatalError("Invalid fixture date") }
        return date
    }

    static var subjects: [Subject] {
        [
            Subject(title: "Ship Report", projectName: "Work", projectPath: ["Work"], sectionName: "Deep Focus",
                    labels: ["Waiting", "Needs Review"], priority: 4, dueDate: date(), isRecurring: true),
            Subject(title: "Write draft", projectName: "Client", projectPath: ["Work", "Client"], sectionName: "Planning",
                    labels: ["writing"], priority: 3, dueDate: date(3, 11), isSubtask: true),
            Subject(title: "Pay invoice", projectName: "Home", projectPath: ["Home"], priority: 2, dueDate: date(3, 9)),
            Subject(title: "Buy milk"),
            Subject(title: "Completed", projectName: "Work", labels: ["Waiting"], priority: 4,
                    dueDate: date(), isCompleted: true)
        ]
    }

    static func resolve(_ value: String) -> Date? {
        switch value.lowercased() {
        case "today", "2026-03-10", "10/03/2026": date()
        case "tomorrow", "march 11", "2026-03-11": date(3, 11)
        case "yesterday": date(3, 9)
        case "today 12:30": date(3, 10, 12, 30)
        default: nil
        }
    }

    static func expect(_ condition: Bool, _ message: String) {
        if condition {
            passed += 1
        } else {
            failed += 1
            print("FAIL: \(message)")
        }
    }

    static func check(
        _ source: String, _ expected: [[String]], subjects: [Subject]? = nil, now: Date? = nil,
        projectNames: [String]? = nil, labelNames: [String]? = nil, sectionNames: [String]? = nil
    ) {
        do {
            let lists = try TodoFilterEngine.evaluate(
                source, subjects: subjects ?? Self.subjects, now: now ?? date(3, 10, 12), calendar: calendar,
                projectNames: projectNames, labelNames: labelNames, sectionNames: sectionNames, dateResolver: resolve)
            let actual = lists.map { $0.map(\.title) }
            expect(actual == expected, "\(source): got \(actual), expected \(expected)")
        } catch {
            expect(false, "\(source) unexpectedly failed: \(error)")
        }
    }

    static func checkError(
        _ source: String, _ reason: TodoFilterError.Reason, _ range: Range<Int>,
        projectNames: [String]? = nil, labelNames: [String]? = nil, sectionNames: [String]? = nil
    ) {
        do {
            _ = try TodoFilterEngine.evaluate(
                source, subjects: [Subject](), now: date(), calendar: calendar,
                projectNames: projectNames, labelNames: labelNames, sectionNames: sectionNames, dateResolver: resolve)
            expect(false, "\(source) returned results instead of throwing")
        } catch {
            expect(error == TodoFilterError(characterRange: range, reason: reason),
                   "\(source): got \(error), expected \(reason) at \(range)")
        }
    }

    static func grammar() throws {
        check("today | overdue & #Work", [["Ship Report"]])
        check("!today & overdue", [["Pay invoice"]])
        check("(today | overdue) & !#Work", [["Pay invoice"]])
        check("(today | overdue) & #Work & !@waiting", [[]])
        check("!(today | overdue)", [["Write draft", "Buy milk"]])
        check("!!today", [["Ship Report"]])
        check("(((today)))", [["Ship Report"]])
        check("today, overdue", [["Ship Report"], ["Pay invoice"]])
        check("today, today | overdue", [["Ship Report"], ["Ship Report", "Pay invoice"]])
        check("search: absent, all", [[], ["Ship Report", "Write draft", "Pay invoice", "Buy milk"]])
        check("today&!@waiting|tomorrow", [["Write draft"]])
        check("no date & !subtask", [["Buy milk"]])
        check("!all", [[]])
        let all = subjects.filter { !$0.isCompleted }
        let parsed = try TodoFilterParser.parse("all", dateResolver: resolve)
        expect(TodoFilterEngine.evaluate(parsed, subjects: subjects, now: date(), calendar: calendar) == [all],
               "AST evaluation preserves original subjects and order")
    }

    static func operands() {
        let cases: [(String, [String])] = [
            ("today", ["Ship Report"]), ("tomorrow", ["Write draft"]), ("overdue", ["Pay invoice"]),
            ("no date", ["Buy milk"]), ("recurring", ["Ship Report"]), ("subtask", ["Write draft"]),
            ("p1", ["Ship Report"]), ("p2", ["Write draft"]), ("p3", ["Pay invoice"]), ("p4", ["Buy milk"]),
            ("#Work", ["Ship Report"]), ("##Work", ["Ship Report", "Write draft"]),
            ("##Client", ["Write draft"]), ("/Planning", ["Write draft"]), ("@waiting", ["Ship Report"]),
            ("no labels", ["Pay invoice", "Buy milk"]), ("search: REPORT", ["Ship Report"]),
            ("search:write draft", ["Write draft"]), ("due before: tomorrow", ["Ship Report", "Pay invoice"]),
            ("due after: yesterday", ["Ship Report", "Write draft"]), ("due before: today", ["Pay invoice"]),
            ("due after: today", ["Write draft"]), ("due before: March 11", ["Ship Report", "Pay invoice"]),
            ("due before: 10/03/2026", ["Pay invoice"]), ("due after: today 12:30", ["Write draft"]),
            ("1 days", ["Ship Report"]), ("2 days", ["Ship Report", "Write draft"]),
            ("next 2 days", ["Ship Report", "Write draft"]),
            ("9223372036854775807 days", ["Ship Report", "Write draft"]),
            ("7 days", ["Ship Report", "Write draft"]), ("all", ["Ship Report", "Write draft", "Pay invoice", "Buy milk"])
        ]
        for (source, expected) in cases { check(source, [expected]) }
        check("ToDaY | OvErDuE & P3", [["Ship Report", "Pay invoice"]])
        check("NO DATE | NO LABELS", [["Pay invoice", "Buy milk"]])
        check("ReCuRrInG & !SuBtAsK", [["Ship Report"]])
        check("NEXT 2 DAYS & DUE BEFORE: TOMORROW", [["Ship Report"]])
        check("SEARCH: sHiP rEpOrT", [["Ship Report"]])
        check("#wOrK & @WaItInG", [["Ship Report"]], projectNames: ["Work"], labelNames: ["waiting"])
        check("/dEeP fOcUs & @nEeDs rEvIeW", [["Ship Report"]],
              labelNames: ["Needs", "Needs Review"], sectionNames: ["Deep Focus"])
        let named = [Subject(title: "Named", projectName: "Big Work", projectPath: ["Area", "Big Work"],
                             sectionName: "Deep Focus", labels: ["Needs Review"])]
        check("#bIg wOrK & @needs review & /deep focus", [["Named"]], subjects: named,
              projectNames: ["Big", "Big Work"], labelNames: ["Needs Review"], sectionNames: ["Deep Focus"])
        check("##area", [["Named"]], subjects: named, projectNames: ["Area", "Big Work"])
        check("#area", [[]], subjects: named, projectNames: ["Area", "Big Work"])
        check("search: 🧑🏽‍💻 café", [["🧑🏽‍💻 Café"]], subjects: [Subject(title: "🧑🏽‍💻 Café")])
        check("#STRASSE & @ΟΣ & search: STRASSE", [["Straße"]],
              subjects: [Subject(title: "Straße", projectName: "Straße", labels: ["ος"])],
              projectNames: ["Straße"], labelNames: ["ος"])
        check("all", [[]], subjects: [])
        check("today\n|\tno   date", [["Ship Report", "Buy milk"]])
    }

    static func errors() {
        let cases: [(String, TodoFilterError.Reason, Range<Int>)] = [
            ("", .missingOperand, 0..<0), ("  ", .missingOperand, 2..<2),
            ("nonsense", .unknownOperand("nonsense"), 0..<8),
            ("this week", .unknownOperand("this"), 0..<4),
            ("last month", .unknownOperand("last"), 0..<4),
            ("assignee: me", .unknownOperand("assignee"), 0..<8),
            ("workspace", .unknownOperand("workspace"), 0..<9),
            ("added by: me", .unknownOperand("added"), 0..<5),
            ("& today", .missingOperand, 0..<1), ("| today", .missingOperand, 0..<1),
            ("today &", .missingOperand, 7..<7), ("today |", .missingOperand, 7..<7),
            ("!", .missingOperand, 1..<1), ("today & | overdue", .missingOperand, 8..<9),
            ("today,", .missingOperand, 6..<6), (",today", .missingOperand, 0..<1),
            ("today,,overdue", .missingOperand, 6..<7),
            ("(", .unbalancedParenthesis, 0..<1), ("(today", .unbalancedParenthesis, 0..<1),
            ("((today)", .unbalancedParenthesis, 0..<1), ("today)", .unbalancedParenthesis, 5..<6),
            (")today", .unbalancedParenthesis, 0..<1), ("()", .missingOperand, 1..<2),
            ("(today &)", .missingOperand, 8..<9), ("(today,overdue)", .unbalancedParenthesis, 0..<1),
            ("#Work @x", .implicitAnd, 6..<8), ("today tomorrow", .implicitAnd, 6..<14),
            ("today (overdue)", .implicitAnd, 6..<7), ("today !overdue", .implicitAnd, 6..<7),
            ("(today overdue)", .implicitAnd, 7..<14), ("(today)(overdue)", .implicitAnd, 7..<8),
            ("#", .missingOperand, 0..<1), ("##", .missingOperand, 0..<2),
            ("@", .missingOperand, 0..<1), ("/", .missingOperand, 0..<1),
            ("search:", .missingOperand, 7..<7), ("search: & today", .missingOperand, 8..<9),
            ("due before:", .missingOperand, 11..<11), ("due after:", .missingOperand, 10..<10),
            ("due before: garbage", .invalidDate("garbage"), 12..<19),
            ("due after: garbage", .invalidDate("garbage"), 11..<18),
            ("0 days", .invalidDayCount, 0..<1), ("next -2 days", .invalidDayCount, 5..<7),
            ("999999999999999999999 days", .invalidDayCount, 0..<21),
            ("next", .missingOperand, 4..<4), ("2 weeks", .unknownOperand("2"), 0..<1),
            ("p5", .unknownOperand("p5"), 0..<2), ("no project", .unknownOperand("no"), 0..<2),
            ("search: report @waiting", .implicitAnd, 15..<23),
            ("@🧑🏽‍💻 today", .implicitAnd, 3..<8)
        ]
        for (source, reason, range) in cases { checkError(source, reason, range) }
        checkError("#Missing", .unknownProject("Missing"), 0..<8, projectNames: ["Work"])
        checkError("##Missing", .unknownProject("Missing"), 0..<9, projectNames: [])
        checkError("@Missing", .unknownLabel("Missing"), 0..<8, labelNames: ["waiting"])
        checkError("/Missing", .unknownSection("Missing"), 0..<8, sectionNames: [])
        checkError("@Needs Review", .unknownLabel("Needs Review"), 0..<13, labelNames: [])
        checkError("@🧑🏽‍💻", .unknownLabel("🧑🏽‍💻"), 0..<2, labelNames: [])
        checkError("#Big Work", .implicitAnd, 5..<9)
        checkError("#Work @x", .implicitAnd, 6..<8, projectNames: ["Work"], labelNames: ["x"])
        checkError("all | due before: garbage", .invalidDate("garbage"), 18..<25)
        checkError("today, due before: garbage", .invalidDate("garbage"), 19..<26)
    }

    static func dateResolution() throws {
        var requests: [String] = []
        let query = try TodoFilterParser.parse("due before: March 11 | due after: yesterday") { value in
            requests.append(value)
            return resolve(value)
        }
        expect(requests == ["March 11", "yesterday"], "date phrases reach the injected resolver intact")
        _ = TodoFilterEngine.evaluate(query, subjects: subjects, now: date(), calendar: calendar)
        expect(requests.count == 2, "dates are resolved once per operand rather than once per subject")
        do {
            _ = try TodoFilterEngine.evaluate(
                "due before: tomorrow", subjects: subjects, now: date(), calendar: calendar, dateResolver: { _ in nil })
            expect(false, "an unavailable date parser must throw")
        } catch {
            expect(error.reason == .invalidDate("tomorrow"), "date parser failure remains a typed error")
        }
    }

    static func boundaries() {
        let tasks = [
            Subject(title: "Yesterday", dueDate: date(3, 9, 23, 59)),
            Subject(title: "Untimed today", dueDate: date()),
            Subject(title: "Midnight", dueDate: date(), hasTime: true),
            Subject(title: "Earlier", dueDate: date(3, 10, 8), hasTime: true),
            Subject(title: "Exact now", dueDate: date(3, 10, 12), hasTime: true),
            Subject(title: "Later", dueDate: date(3, 10, 18), hasTime: true),
            Subject(title: "Tomorrow", dueDate: date(3, 11)),
            Subject(title: "Missing"),
            Subject(title: "Completed overdue", dueDate: date(3, 9), isCompleted: true)
        ]
        check("overdue", [["Yesterday"]], subjects: tasks, now: date())
        check("today", [["Untimed today", "Midnight", "Earlier", "Exact now", "Later"]], subjects: tasks, now: date())
        check("overdue", [["Yesterday", "Midnight", "Earlier"]], subjects: tasks, now: date(3, 10, 12))
        check("overdue", [["Yesterday", "Untimed today", "Midnight", "Earlier", "Exact now", "Later"]],
              subjects: tasks, now: date(3, 11))
        check("today", [["Tomorrow"]], subjects: tasks, now: date(3, 11))
        check("1 days", [["Untimed today", "Midnight", "Earlier", "Exact now", "Later"]], subjects: tasks)
        let spring = [Subject(title: "Start", dueDate: date(3, 28)),
                      Subject(title: "DST", dueDate: date(3, 29, 23, 59)),
                      Subject(title: "End", dueDate: date(3, 30))]
        check("2 days", [["Start", "DST"]], subjects: spring, now: date(3, 28, 12))
        check("tomorrow", [["DST"]], subjects: spring, now: date(3, 28, 12))
        check("today", [["DST"]], subjects: spring, now: date(3, 29, 12))
        let autumn = [Subject(title: "Start", dueDate: date(10, 24)),
                      Subject(title: "DST", dueDate: date(10, 25, 23, 59)),
                      Subject(title: "End", dueDate: date(10, 26))]
        check("next 2 days", [["Start", "DST"]], subjects: autumn, now: date(10, 24, 12))
        check("overdue", [["Start"]], subjects: autumn, now: date(10, 25, 12))
        let endOfYear = [Subject(title: "Year end", dueDate: date(12, 31))]
        check("tomorrow", [["Year end"]], subjects: endOfYear, now: date(12, 30, 23, 59))
    }

    static func main() {
        do {
            try grammar()
            try dateResolution()
        } catch { expect(false, "AST parsing failed: \(error)") }
        operands()
        errors()
        boundaries()
        print("Todo filters: \(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
    }
}

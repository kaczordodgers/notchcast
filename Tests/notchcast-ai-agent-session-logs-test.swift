// notchcast-sources: Tinycast/Features/AgentSessions/Model/*.swift
// notchcast-sources: Tinycast/Features/AgentSessions/Pricing/*.swift
// notchcast-sources: Tinycast/Features/AgentSessions/Service/*.swift
// notchcast-sources: Tinycast/Features/AgentSessions/AgentSessionsModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: -strict-concurrency=complete -warnings-as-errors
import Foundation
import SQLite3
import Synchronization

@main
struct AgentSessionTests {
    static let timestamp = "2026-01-02T03:04:05.000Z"
    static let nextTimestamp = "2026-01-02T03:05:05Z"
    static let milliseconds: Int64 = 1_767_323_045_000

    @MainActor
    static func main() async throws {
        guard let resolved = realpath(FileManager.default.temporaryDirectory.path, nil) else {
            fatalError("Synthetic fixture root must resolve")
        }
        let temporary = URL(fileURLWithPath: String(cString: resolved)).appendingPathComponent(UUID().uuidString)
        free(resolved)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try sharedIdentity(temporary.appendingPathComponent("shared"))
        localDays()
        try claude(temporary.appendingPathComponent("claude"))
        try codex(temporary.appendingPathComponent("codex"))
        try copilot(temporary.appendingPathComponent("copilot"))
        try database(temporary.appendingPathComponent("opencode-v1"), version2: false)
        try database(temporary.appendingPathComponent("opencode-v2"), version2: true)
        try incremental(temporary.appendingPathComponent("incremental"))
        try streamed(temporary.appendingPathComponent("streamed"))
        try exclusion(temporary.appendingPathComponent("exclusion"))
        try await lifecycle(temporary.appendingPathComponent("lifecycle"))
        print("PASS: four formats, malformed input, bounded streaming, exclusion, incremental refresh and lifecycle")
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }

    static func sharedIdentity(_ root: URL) throws {
        for (path, input) in [("session.jsonl", 100), ("session/subagents/child.jsonl", 200)] {
            try append(["type": "assistant", "sessionId": "parent", "timestamp": timestamp,
                        "message": ["id": path, "model": "gpt-4.1", "usage": ["input_tokens": input]]],
                       to: root.appendingPathComponent(path))
        }
        var index = AgentSessionIndex()
        let result = try index.refresh(roots: [.init(provider: .claude, url: root)])
        expect(result.sessions.count == 1, "Shared native identity stays one session")
        expect(result.sessions[0].usage.reduce(Int64(0)) { $0 + $1.tokens.input } == 300,
               "Parent and subagent usage must both survive")
        let copyRoot = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: copyRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: copyRoot) }
        try FileManager.default.copyItem(at: root.appendingPathComponent("session.jsonl"),
                                         to: copyRoot.appendingPathComponent("session.jsonl"))
        var copied = AgentSessionIndex(calendar: index.calendar)
        let bothRoots = try copied.refresh(roots: [.init(provider: .claude, url: root),
                                                   .init(provider: .claude, url: copyRoot)])
        expect(bothRoots.sessions[0].usage.reduce(Int64(0)) { $0 + $1.tokens.input } == 300,
               "A file copied between roots counts once")
        let unchanged = try index.refresh(roots: [.init(provider: .claude, url: root)])
        expect(unchanged.sessions == result.sessions, "Shared usage is stable across refreshes")
    }

    static func localDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        var accumulator = AgentSessionAccumulator(provider: .claude, id: "local", calendar: calendar)
        let before = AgentSessionAccumulator.date("2026-01-01T22:30:00Z")!
        let after = AgentSessionAccumulator.date("2026-01-01T23:30:00Z")!
        accumulator.addUsage(.init(input: 100), model: "gpt-4.1", at: before)
        accumulator.addUsage(.init(input: 200), model: "gpt-4.1", at: after)
        expect(accumulator.session.usage.count == 2, "Warsaw midnight splits usage into local days")
        expect(accumulator.session.usage[1].day == calendar.startOfDay(for: after), "Local day retained")
        let report = AgentSessionPricing.report([accumulator.session], calendar: calendar)
        expect(report?.days[calendar.startOfDay(for: before)]?.costUSD == Decimal(string: "0.0002"),
               "Before midnight is priced on the previous local day")
        expect(report?.days[calendar.startOfDay(for: after)]?.costUSD == Decimal(string: "0.0004"),
               "After midnight is priced on the next local day")
    }

    static func append(_ object: [String: Any], to url: URL) throws {
        var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        data.append(10)
        try append(data, to: url)
    }

    static func append(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try data.write(to: url)
            return
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    static func claude(_ root: URL) throws {
        let file = root.appendingPathComponent("project/session.jsonl")
        try append(["type": "user", "sessionId": "claude-session", "cwd": "/synthetic/project",
                    "timestamp": timestamp, "message": ["content": "SYNTHETIC_TRANSCRIPT_SENTINEL"]], to: file)
        func response(_ output: Int) -> [String: Any] {
            ["type": "assistant", "sessionId": "claude-session", "timestamp": nextTimestamp,
             "message": ["id": "response", "model": "claude-test", "stop_reason": "end_turn",
                         "usage": ["input_tokens": 100, "output_tokens": output,
                                   "cache_read_input_tokens": 40, "cache_creation_input_tokens": 10]]]
        }
        try append(response(5), to: file)
        try append(response(20), to: file)
        try append(response(5), to: file)
        try append(response(20), to: file)
        try append(Data("malformed\n{\"type\":\n[]\n".utf8), to: file)
        var index = AgentSessionIndex()
        let result = try index.refresh(roots: [.init(provider: .claude, url: root)])
        expect(result.sessions.count == 1, "Claude session discovered: \(result)")
        let session = result.sessions[0]
        expect(session.id == "claude:claude-session", "Claude native session ID")
        expect(session.project == "/synthetic/project" && session.model == "claude-test", "Claude context")
        expect(session.startedAt != nil && session.endedAt != nil, "Fractional and whole-second timestamps")
        expect(session.usage.count == 1, "Usage grouped by UTC day and model")
        expect(session.usage[0].tokens == .init(input: 100, cacheRead: 40, cacheWrite: 10, output: 20),
               "Streamed Claude response merged without double counting")
        expect(result.statistics.malformedLines == 3, "Malformed records isolated")
        expect(!String(reflecting: result).contains("SYNTHETIC_TRANSCRIPT_SENTINEL"), "No transcript retained")
        expect(!session.isWorking(at: session.endedAt!), "Completed session quiet")
        expect(AgentSessionAccumulator.count(true) == 0, "Boolean tokens rejected")
        expect(AgentSessionAccumulator.count(-5) == 0, "Negative tokens rejected")
        expect(AgentSessionAccumulator.count(1.5) == 0, "Fractional tokens rejected")
        expect(AgentSessionAccumulator.count(Double.infinity) == 0, "Non-finite tokens rejected")
        expect((AgentSession.Tokens(input: .max) + .init(input: 1)).input == .max, "Token overflow bounded")
    }

    static func codex(_ root: URL) throws {
        let file = root.appendingPathComponent("2026/01/02/rollout.jsonl")
        try append(["type": "session_meta", "timestamp": timestamp,
                    "payload": ["id": "codex-session", "cwd": "/synthetic/codex"]], to: file)
        try append(["type": "turn_context", "payload": ["model": "model-one"]], to: file)
        func total(_ input: Int, _ cached: Int, _ output: Int) -> [String: Any] {
            ["type": "event_msg", "timestamp": nextTimestamp,
             "payload": ["type": "token_count", "info": ["total_token_usage": [
                "input_tokens": input, "cached_input_tokens": cached, "output_tokens": output,
                "reasoning_output_tokens": 5]]]]
        }
        try append(total(100, 20, 10), to: file)
        try append(total(100, 20, 10), to: file)
        try append(["type": "turn_context", "payload": ["model": "model-two"]], to: file)
        try append(total(200, 30, 40), to: file)
        try append(["type": "event_msg", "timestamp": nextTimestamp, "payload": ["type": "task_complete"]], to: file)
        try append(total(200, 30, 40), to: file)
        var index = AgentSessionIndex()
        let result = try index.refresh(roots: [.init(provider: .codex, url: root)])
        let session = result.sessions[0]
        expect(session.id == "codex:codex-session" && session.project == "/synthetic/codex", "Codex metadata")
        expect(session.endedAt != nil, "Codex completion")
        expect(session.usage.count == 2, "Model-specific usage")
        expect(session.usage[0].tokens.input == 80 && session.usage[0].tokens.cacheRead == 20, "Cache disjoint from input")
        expect(session.usage[1].tokens.input == 90 && session.usage[1].tokens.output == 30, "Running totals across model change")
        let explicit = root.appendingPathComponent("explicit.jsonl")
        let record: [String: Any] = ["type": "token_usage_record", "timestamp": timestamp,
            "payload": ["response_id": "r1", "usage": ["input_tokens": 50, "output_tokens": 15]]]
        try append(record, to: explicit)
        try append(record, to: explicit)
        let explicitResult = try index.refresh(roots: [.init(provider: .codex, url: explicit)])
        expect(explicitResult.sessions[0].usage[0].tokens.input == 50, "Explicit usage record deduplication")
        expect(explicitResult.sessions[0].model == nil, "Unknown model preserved")
    }

    static func copilot(_ root: URL) throws {
        let file = root.appendingPathComponent("session/events.jsonl")
        try append(["type": "session.start", "timestamp": timestamp,
                    "data": ["sessionId": "copilot-session", "selectedModel": "model-test",
                             "context": ["cwd": "/synthetic/copilot"]]], to: file)
        try append(["type": "assistant.message", "timestamp": timestamp,
                    "data": ["phase": "commentary", "toolRequests": [["id": "synthetic-tool"]]]], to: file)
        try append(["type": "assistant.turn_end", "timestamp": timestamp, "data": [:]], to: file)
        var index = AgentSessionIndex()
        let working = try index.refresh(roots: [.init(provider: .copilot, url: root)])
        expect(working.sessions[0].endedAt == nil, "Tool iteration does not end Copilot session")
        let shutdown: [String: Any] = ["type": "session.shutdown", "timestamp": nextTimestamp,
            "data": ["modelMetrics": ["model-test": [
                "tokenDetails": ["input": ["tokenCount": 42], "cache_read": ["tokenCount": 12]],
                "usage": ["inputTokens": 999, "outputTokens": 13, "cacheWriteTokens": 4]]]]]
        try append(shutdown, to: file)
        try append(shutdown, to: file)
        let session = try index.refresh(roots: [.init(provider: .copilot, url: root)]).sessions[0]
        expect(session.id == "copilot:copilot-session" && session.project == "/synthetic/copilot", "Copilot context")
        expect(session.usage[0].tokens == .init(input: 42, cacheRead: 12, cacheWrite: 4, output: 13),
               "Copilot detail precedence, fallback and cumulative deduplication")
        expect(session.endedAt != nil, "Copilot shutdown")
    }

    static func sql(_ database: OpaquePointer?, _ statement: String) throws {
        let status = sqlite3_exec(database, statement, nil, nil, nil)
        guard status == SQLITE_OK else { throw NSError(domain: "synthetic-sql", code: Int(status)) }
    }

    static func database(_ root: URL, version2: Bool) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("opencode.db")
        var database: OpaquePointer?
        expect(sqlite3_open(file.path, &database) == SQLITE_OK, "Synthetic database created")
        defer { sqlite3_close(database) }
        try sql(database, "PRAGMA journal_mode = WAL")
        let sessions = version2 ? "session_v2" : "session"
        let messages = version2 ? "session_message" : "message"
        try sql(database, """
            CREATE TABLE \(sessions) (id TEXT PRIMARY KEY, directory TEXT, time_created INTEGER, time_updated INTEGER)
            """)
        try sql(database, """
            CREATE TABLE \(messages) (id TEXT PRIMARY KEY, session_id TEXT,
                time_created INTEGER, time_updated INTEGER, data TEXT)
            """)
        try sql(database, "INSERT INTO \(sessions) VALUES ('s1', '/synthetic/opencode', \(milliseconds), \(milliseconds))")
        let metadata = """
            {"role":"assistant","modelID":"open-test","tokens":{"input":21,"output":8,
            "reasoning":3,"cache":{"read":9,"write":2}},"cost":0.125,"time":{"completed":\(milliseconds + 1000)}}
            """
        try sql(database, "INSERT INTO \(messages) VALUES ('m1', 's1', \(milliseconds), \(milliseconds), '\(metadata)')")
        try sql(database, "INSERT INTO \(messages) VALUES ('bad', 's1', \(milliseconds), \(milliseconds), 'malformed')")
        var index = AgentSessionIndex()
        let roots = [AgentSessionIndex.Root(provider: .opencode, url: file)]
        let bytesBefore = try Data(contentsOf: file)
        let result = try index.refresh(roots: roots)
        let bytesAfter = try Data(contentsOf: file)
        expect(bytesBefore == bytesAfter, "OpenCode database never mutated by reader")
        expect(result.issues.isEmpty && result.sessions.count == 1, "OpenCode supported schema")
        let session = result.sessions[0]
        expect(session.model == "open-test" && session.project == "/synthetic/opencode", "OpenCode context")
        expect(session.usage[0].tokens == .init(input: 21, cacheRead: 9, cacheWrite: 2, output: 11, reasoning: 3),
               "OpenCode token kinds")
        expect(session.usage[0].reportedCost == 0.125, "Reported cost exposed for pricing")
        let unchanged = try index.refresh(roots: roots)
        expect(unchanged.statistics.databaseRowsRead == 0, "Unchanged database messages not read")
        try sql(database, """
            UPDATE \(messages) SET data = replace(data, '\"input\":21', '\"input\":31'), time_updated = time_updated + 1
            """)
        let updated = try index.refresh(roots: roots)
        expect(updated.sessions[0].usage[0].tokens.input == 31, "In-place message update replaces aggregate")
        try sql(database, "DELETE FROM \(sessions)")
        let deleted = try index.refresh(roots: roots)
        expect(deleted.sessions.isEmpty, "Deleted database sessions evicted")
        expect(sqlite3_db_readonly(database, "main") == 0, "Fixture writer connection remains independent")
    }

    static func incremental(_ root: URL) throws {
        let file = root.appendingPathComponent("session.jsonl")
        let line = "{\"type\":\"user\",\"timestamp\":\"\(timestamp)\"}\n"
        let bytes = Data(line.utf8)
        try append(bytes, to: file)
        var index = AgentSessionIndex()
        let roots = [AgentSessionIndex.Root(provider: .claude, url: root)]
        let first = try index.refresh(roots: roots)
        expect(first.statistics.bytesRead == bytes.count, "First refresh reads fixture")
        let unchanged = try index.refresh(roots: roots)
        expect(unchanged.statistics.bytesRead == 0, "Unchanged file never reopened")
        try append(Data(bytes.prefix(20)), to: file)
        let partial = try index.refresh(roots: roots)
        expect(partial.statistics.bytesRead == 20, "Partial line offset retained")
        try append(Data(bytes.dropFirst(20)), to: file)
        let completed = try index.refresh(roots: roots)
        expect(completed.statistics.bytesRead == bytes.count - 20, "Only suffix read")
        let replacement = "{\"type\":\"user\",\"timestamp\":\"\(timestamp)\",\"cwd\":\"/replacement\"}\n"
        try Data(replacement.utf8).write(to: file, options: .atomic)
        let replaced = try index.refresh(roots: roots)
        expect(replaced.sessions[0].project == "/replacement", "Replaced inode resets")
        try bytes.write(to: file)
        let truncated = try index.refresh(roots: roots)
        expect(truncated.statistics.bytesRead == bytes.count && truncated.sessions[0].project == nil, "Truncation resets")
        try FileManager.default.removeItem(at: file)
        let deleted = try index.refresh(roots: roots)
        expect(deleted.sessions.isEmpty, "Deleted files evicted")
        var quiet = first.sessions[0]
        quiet.endedAt = nil
        expect(quiet.isWorking(at: quiet.lastActivityAt!.addingTimeInterval(599)), "Recent work active")
        expect(!quiet.isWorking(at: quiet.lastActivityAt!.addingTimeInterval(600)), "Ten minutes silence quiet")
    }

    static func streamed(_ root: URL) throws {
        let file = root.appendingPathComponent("huge.jsonl")
        try append(Data(), to: file)
        let handle = try FileHandle(forWritingTo: file)
        let block = Data(repeating: 120, count: AgentSessionIndex.chunkSize)
        for _ in 0..<384 { try handle.write(contentsOf: block) }
        try handle.write(contentsOf: Data("\n".utf8))
        try handle.close()
        try append(["type": "user", "timestamp": timestamp, "cwd": "/after-huge-line"], to: file)
        var index = AgentSessionIndex()
        let result = try index.refresh(roots: [.init(provider: .claude, url: root)])
        expect(result.statistics.bytesRead > 24_000_000, "Huge fixture streamed in full")
        expect(result.statistics.largestRead <= AgentSessionIndex.chunkSize, "Bounded read requests")
        expect(result.statistics.malformedLines == 1, "Oversized line discarded once")
        expect(result.sessions[0].project == "/after-huge-line", "Parsing resumes after huge line")
    }

    static func exclusion(_ root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let config = root.appendingPathComponent("private.env")
        let missing = try AgentSessionExclusions.load(from: config)
        expect(missing.isEmpty, "Missing private config excludes nothing")
        let fixturePath = root.appendingPathComponent("sub/private-fixture.jsonl")
        expect(AgentSessionIndex.allows(fixturePath, excluding: missing), "No file allows otherwise excluded paths")
        let marker = root.appendingPathComponent("must-not-exist")
        try Data("OTHER_KEY=value\ntouch \"\(marker.path)\"\n".utf8).write(to: config)
        let noKey = try AgentSessionExclusions.load(from: config)
        expect(noKey.isEmpty, "Missing key excludes nothing")
        try Data("NOTCHCAST_AGENT_SESSIONS_EXCLUDE=private-fixture,other-private,,\n".utf8).write(to: config)
        let prefixes = try AgentSessionExclusions.load(from: config)
        expect(prefixes == ["private-fixture", "other-private"], "Plain comma-separated prefixes parsed")
        let forms = [
            "export NOTCHCAST_AGENT_SESSIONS_EXCLUDE=a,b": ["a", "b"],
            "NOTCHCAST_AGENT_SESSIONS_EXCLUDE=\"a,b\"": ["a", "b"],
            "NOTCHCAST_AGENT_SESSIONS_EXCLUDE='A,b'": ["a", "b"],
            "  NOTCHCAST_AGENT_SESSIONS_EXCLUDE=agent_a.b,c\nOTHER=1\n": ["agent_a.b", "c"],
            "NOTCHCAST_AGENT_SESSIONS_EXCLUDE=": [],
            "NOTCHCAST_AGENT_SESSIONS_EXCLUDE=agent-abc  # note $(x) `y`": ["agent-abc"],
            "NOTCHCAST_AGENT_SESSIONS_EXCLUDE=\"agent-abc\" # note": ["agent-abc"],
            "export\tNOTCHCAST_AGENT_SESSIONS_EXCLUDE=agent-abc\t": ["agent-abc"],
        ]
        for (text, expected) in forms {
            try Data(text.utf8).write(to: config)
            let parsed = try AgentSessionExclusions.load(from: config)
            expect(parsed == expected, "Shell form parsed: \(text)")
        }
        let malformed = [
            "export FOO=1; export NOTCHCAST_AGENT_SESSIONS_EXCLUDE=agent-abc",
            "NOTCHCAST_AGENT_SESSIONS_EXCLUDE=old; NOTCHCAST_AGENT_SESSIONS_EXCLUDE=agent-new",
            "NOTCHCAST_AGENT_SESSIONS_EXCLUDE = x",
            "NOTCHCAST_AGENT_SESSIONS_EXCLUDE =x",
            "NOTCHCAST_AGENT_SESSIONS_EXCLUDE=agent-\"abc\"",
            "NOTCHCAST_AGENT_SESSIONS_EXCLUDE=\"agent\"-abc",
            "NOTCHCAST_AGENT_SESSIONS_EXCLUDE=\"a,b'",
            "NOTCHCAST_AGENT_SESSIONS_EXCLUDE=good\nNOTCHCAST_AGENT_SESSIONS_EXCLUDE = bad",
            "NOTCHCAST_AGENT_SESSIONS_EXCLUDE=old\nNOTCHCAST_AGENT_SESSIONS_EXCLUDE=new",
            "NOTCHCAST_AGENT_SESSIONS_EXCLUDE=kept\n# NOTCHCAST_AGENT_SESSIONS_EXCLUDE=comment",
            "export NOTCHCAST_AGENT_SESSIONS_EXCLUDE=agent-abc; export OTHER=1",
            "NOTCHCAST_AGENT_SESSIONS_EXCLUDE=\"a, b\"",
            "NOTCHCAST_AGENT_SESSIONS_EXCLUDE=abc\r,ghi",
            "NOTCHCAST_AGENT_\\\nSESSIONS_EXCLUDE=ghi",
            "NOTCHCAST_AGENT_SESSIONS_EXCLUDE=agent-a\\\n,agent-b",
            "NOTCHCAST_AGENT_SESSIONS_EXCLUDE= # note \\\nNOTCHCAST_AGENT_SESSIONS_EXCLUDE=secret",
            "NOTCHCAST_AGENT_SESSIONS_EXCLUDE=abc # c:\\\\\nNOTCHCAST_AGENT_SESSIONS_EXCLUDE=secret",
            "NOTCHCAST_AGENT_SESSIONS_EXCLUDE='ab\\\nc'",
            "export NOTCHCAST_AGENT_SESSIONS_EXCLUD$'E'=secret",
            "export NOTCHCAST_AGENT_SESSIONS_EXCLUD$\"E\"=secret",
            "export NOTCHCAST_AGENT_SESSIONS_EXCLU{D,D}E=secret",
            "export N{O,O}TCHCAST_AGENT_SESSIONS_EXCLUDE=secret\nX=1",
            "NOTCHCAST_AGENT_SESSIONS_EXCLUDE=abc\nexport NOTCHCAST_AGENT_SESSIONS_EXCLU{D..D}E=secret",
            "export NOTCHCAST_AGENT_SESSIONS_EXCLUD$(printf E)=secret",
            "NOTCHCAST_AGENT_SESSIONS_EXCLUDE=abc\u{2028},ghi",
            "export NOTCHCAST_AGENT_SESSIONS_EXCLUD\"E\"=ghi",
            "export NOTCHCAST_AGENT_SESSIONS_EXCLUD\\E=ghi",
            "NOTCHCAST_AGENT_SESSIONS_EXCLUDE=abc\nexport NOTCHCAST_AGENT_SESSIONS_EXCLUD'E'=ghi",
            "NOTCHCAST_AGENT_SESSIONS_EXCLUDE=agent-abc#note",
            "NOTCHCAST_AGENT_SESSIONS_EXCLUDE=$ID",
            "NOTCHCAST_AGENT_SESSIONS_EXCLUDE=\"$ID,agent-other\"",
            "NOTCHCAST_AGENT_SESSIONS_EXCLUDE=${ID}",
            "NOTCHCAST_AGENT_SESSIONS_EXCLUDE=agent\\-secret",
            "NOTCHCAST_AGENT_SESSIONS_EXCLUDE=\"agent-a\n,agent-b\"",
            "NOTCHCAST_AGENT_SESSIONS_EXCLUDE=`id`",
            "NOTCHCAST_AGENT_SESSIONS_EXCLUDE=$(id)",
            "NOTCHCAST_AGENT_SESSIONS_EXCLUDE=agent-a; . more.inc",
            "NOTCHCAST_AGENT_SESSIONS_EXCLUDE=a\nif false; then NOTCHCAST_AGENT_SESSIONS_EXCLUDE=b; fi",
            "NOTCHCAST_AGENT_SESSIONS_EXCLUDE=a\nf() { NOTCHCAST_AGENT_SESSIONS_EXCLUDE=b; }",
            "NOTCHCAST_AGENT_SESSIONS_EXCLUDE=a\ncat <<EOF\nNOTCHCAST_AGENT_SESSIONS_EXCLUDE=b\nEOF",
            "NOTCHCAST_AGENT_SESSIONS_EXCLUDE=a&&OTHER=1",
            "NOTCHCAST_AGENT_SESSIONS_EXCLUDE=a>/dev/null",
            "NOTCHCAST_AGENT_SESSIONS_EXCLUDE=a|b",
            "NOTCHCAST_AGENT_SESSIONS_EXCLUDE=a<b",
            "NOTCHCAST_AGENT_SESSIONS_EXCLUDE=(a)",
        ]
        for text in malformed {
            try Data(text.utf8).write(to: config)
            expect((try? AgentSessionExclusions.load(from: config)) == nil, "Malformed form throws: \(text)")
        }
        expect(!FileManager.default.fileExists(atPath: marker.path), "Private config is never executed")
        expect(!AgentSessionIndex.allows(fixturePath, excluding: prefixes), "Excluded file prefix rejected")
        expect(!AgentSessionIndex.allows(root.appendingPathComponent("PRIVATE-FIXTURE-wal"), excluding: prefixes),
               "Excluded side file prefix is case insensitive")
        expect(!AgentSessionIndex.allows(root.appendingPathComponent("other-private/log.jsonl"), excluding: prefixes),
               "Every configured prefix is applied")
        expect(AgentSessionIndex.allows(root.appendingPathComponent("sub/session.jsonl"), excluding: prefixes),
               "Other files allowed")
        let forbidden = root.appendingPathComponent("nested/private-fixture")
        try FileManager.default.createDirectory(at: forbidden, withIntermediateDirectories: true)
        defer { expect(rmdir(forbidden.path) == 0, "Empty excluded fixture removed without opening it") }
        let safe = root.appendingPathComponent("safe/session.jsonl")
        try append(["type": "user", "timestamp": timestamp], to: safe)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("alias"), withDestinationURL: forbidden)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("loop"), withDestinationURL: root)
        let accesses = Mutex<[URL]>([])
        var index = AgentSessionIndex { url in
            expect(AgentSessionIndex.allows(url, excluding: prefixes), "Excluded folder never touched")
            accesses.withLock { $0.append(url) }
        }
        index.excludedPathComponentPrefixes = prefixes
        let result = try index.refresh(roots: [.init(provider: .claude, url: root)])
        expect(result.sessions.count == 1, "Sibling indexed and symlinks skipped")
        let before = accesses.withLock { $0.count }
        let excluded = try index.refresh(roots: [.init(provider: .claude, url: forbidden),
            .init(provider: .opencode, url: forbidden.appendingPathComponent("opencode.db")),
            .init(provider: .claude, url: root.appendingPathComponent("nested/PRIVATE-FIXTURE"))])
        expect(excluded.sessions.isEmpty && accesses.withLock { $0.count } == before, "Excluded roots do zero I/O")
        expect(!AgentSessionIndex.allows(forbidden.appendingPathComponent("../escape"), excluding: prefixes),
               "Traversal spelling rejected")
        expect(AgentSessionIndex.Root.defaults(home: root).count == 6, "Default locations built without accessing them")
    }

    @MainActor
    static func lifecycle(_ root: URL) async throws {
        let file = root.appendingPathComponent("lazy.jsonl")
        try append(["type": "user", "timestamp": timestamp], to: file)
        let module = AgentSessionsModule(roots: [.init(provider: .claude, url: root)],
            privateConfigURL: root.appendingPathComponent("missing-private.env"))
        module.start()
        await Task.yield()
        expect(module.snapshot.sessions.isEmpty, "Enable remains lazy before demand")
        module.setDemand(true)
        for _ in 0..<100 where module.snapshot.sessions.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        expect(module.snapshot.sessions.count == 1, "Demand starts off-main scan")
        module.refresh()
        module.stop()
        try await Task.sleep(for: .milliseconds(30))
        expect(module.snapshot.sessions.isEmpty, "Stop rejects late results and clears memory")
        let suite = "session-harness-" + UUID().uuidString
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        expect(!preferences.isOn(.agentSessions), "Feature defaults off")
        expect(preferences.isOn(.island), "Existing defaults preserved")
        expect(!NotchcastFeature.agentSessions.needsIsland, "Feature switch independent of island")
        preferences.set(.agentSessions, true)
        expect(preferences.isOn(.agentSessions), "Explicit opt-in applies")
        expect(!NotchcastPreferences(suiteName: suite).isOn(.agentSessions), "Hidden switch reloads off")
    }
}

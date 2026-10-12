import Foundation

public struct ClaudeEvent: Codable, Sendable {
    public let schemaVersion: Int
    public let eventId: String
    public let eventType: String
    public let sessionId: String
    public let timestamp: Date
    public let cwd: String?
    public let toolName: String?
    public let agentId: String?
    public let agentType: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case eventId = "event_id"
        case eventType = "event_type"
        case sessionId = "session_id"
        case timestamp, cwd
        case toolName = "tool_name"
        case agentId = "agent_id"
        case agentType = "agent_type"
    }

    public init(schemaVersion: Int = 1, eventId: String = UUID().uuidString,
                eventType: String, sessionId: String, timestamp: Date = .now,
                cwd: String? = nil, toolName: String? = nil,
                agentId: String? = nil, agentType: String? = nil) {
        self.schemaVersion = schemaVersion
        self.eventId = eventId
        self.eventType = eventType
        self.sessionId = sessionId
        self.timestamp = timestamp
        self.cwd = cwd
        self.toolName = toolName
        self.agentId = agentId
        self.agentType = agentType
    }
}

public enum SessionState: String, Codable, Sendable {
    case ready, thinking, reading, coding, running
    case waitingPermission = "waiting_permission"
    case waitingInput = "waiting_input"
    case subagents, completed, error, possiblyStale = "possibly_stale", ended
}

public struct ClaudeSession: Codable, Sendable, Equatable {
    public let id: String
    public var projectPath: String?
    public var projectName: String
    public var startedAt: Date?
    public var lastEventAt: Date
    public var state: SessionState
    public var currentTool: String?
    public var toolsUsed: Int
    public var needsAttention: Bool
    public var lastError: String?

    public init(id: String, projectPath: String? = nil, projectName: String = "Untitled Session",
                lastEventAt: Date = .now, state: SessionState = .ready) {
        self.id = id
        self.projectPath = projectPath
        self.projectName = projectName
        self.lastEventAt = lastEventAt
        self.state = state
        self.startedAt = nil
        self.currentTool = nil
        self.toolsUsed = 0
        self.needsAttention = false
        self.lastError = nil
    }
}

public final class SessionStore: @unchecked Sendable {
    public private(set) var sessions: [String: ClaudeSession] = [:]
    private var seenEventIds: Set<String> = []
    private let decoder: JSONDecoder

    public init() {
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    @discardableResult
    public func apply(line: Data) -> ClaudeSession? {
        guard let event = try? decoder.decode(ClaudeEvent.self, from: line) else { return nil }
        return apply(event)
    }

    @discardableResult
    public func apply(_ event: ClaudeEvent) -> ClaudeSession? {
        guard !event.eventId.isEmpty, !event.sessionId.isEmpty, !seenEventIds.contains(event.eventId) else { return nil }
        seenEventIds.insert(event.eventId)
        var session = sessions[event.sessionId] ?? ClaudeSession(id: event.sessionId)
        if session.state == .ended && event.eventType != "SessionStart" { return session }
        session.projectPath = event.cwd ?? session.projectPath
        session.projectName = event.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? session.projectName
        session.lastEventAt = max(session.lastEventAt, event.timestamp)
        switch event.eventType {
        case "SessionStart": session.state = .ready; session.startedAt = event.timestamp; session.needsAttention = false
        case "UserPromptSubmit": session.state = .thinking; session.needsAttention = false
        case "PreToolUse":
            session.currentTool = event.toolName
            session.toolsUsed += 1
            session.state = Self.state(for: event.toolName)
        case "PostToolUse": session.state = .thinking; session.currentTool = nil
        case "PostToolUseFailure", "StopFailure": session.state = .error; session.lastError = event.toolName; session.needsAttention = true
        case "PermissionRequest": session.state = .waitingPermission; session.needsAttention = true
        case "Notification": session.state = .waitingInput; session.needsAttention = true
        case "SubagentStart": session.state = .subagents
        case "Stop": session.state = .completed; session.currentTool = nil
        case "SessionEnd": session.state = .ended; session.currentTool = nil
        default: break
        }
        sessions[event.sessionId] = session
        return session
    }

    public func markStale(now: Date = .now, after interval: TimeInterval = 90) {
        for id in sessions.keys where sessions[id]?.state != .ended {
            guard let last = sessions[id]?.lastEventAt, now.timeIntervalSince(last) >= interval else { continue }
            sessions[id]?.state = .possiblyStale
        }
    }

    private static func state(for tool: String?) -> SessionState {
        switch tool {
        case "Read", "Glob", "Grep", "WebFetch", "WebSearch": return .reading
        case "Edit", "Write", "NotebookEdit": return .coding
        case "Bash", "PowerShell": return .running
        default: return .thinking
        }
    }
}

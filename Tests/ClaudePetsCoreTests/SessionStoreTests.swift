import XCTest
@testable import ClaudePetsCore

final class SessionStoreTests: XCTestCase {
    func testToolStateAndSessionIsolation() {
        let store = SessionStore()
        _ = store.apply(ClaudeEvent(eventType: "SessionStart", sessionId: "a", cwd: "/tmp/one"))
        _ = store.apply(ClaudeEvent(eventType: "PreToolUse", sessionId: "a", toolName: "Edit"))
        _ = store.apply(ClaudeEvent(eventType: "SessionStart", sessionId: "b", cwd: "/tmp/two"))
        XCTAssertEqual(store.sessions["a"]?.state, .coding)
        XCTAssertEqual(store.sessions["b"]?.projectName, "two")
    }

    func testDuplicateAndLateEventsDoNotReopenEndedSession() {
        let store = SessionStore()
        let start = ClaudeEvent(eventId: "same", eventType: "SessionStart", sessionId: "a")
        XCTAssertNotNil(store.apply(start))
        XCTAssertNil(store.apply(start))
        _ = store.apply(ClaudeEvent(eventType: "SessionEnd", sessionId: "a"))
        _ = store.apply(ClaudeEvent(eventType: "PreToolUse", sessionId: "a", toolName: "Bash"))
        XCTAssertEqual(store.sessions["a"]?.state, .ended)
    }

    func testPermissionRequiresAttention() {
        let store = SessionStore()
        _ = store.apply(ClaudeEvent(eventType: "PermissionRequest", sessionId: "a"))
        XCTAssertEqual(store.sessions["a"]?.state, .waitingPermission)
        XCTAssertEqual(store.sessions["a"]?.needsAttention, true)
    }
}

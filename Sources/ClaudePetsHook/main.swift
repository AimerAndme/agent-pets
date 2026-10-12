import Foundation
import ClaudePetsCore

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

let socketPath = CommandLine.arguments.dropFirst().first ?? "/tmp/claude-pets.sock"
let input = FileHandle.standardInput.readDataToEndOfFile()
guard !input.isEmpty else { exit(0) }

// Claude Code sends one JSON object. We normalize only the fields needed by Pets.
let raw = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any]
guard let raw, let sessionId = raw["session_id"] as? String, !sessionId.isEmpty else { exit(0) }
let eventType = (raw["hook_event_name"] as? String) ?? (raw["event_type"] as? String) ?? "Unknown"
let cwd = raw["cwd"] as? String
let toolName = raw["tool_name"] as? String
let event = ClaudeEvent(eventType: eventType, sessionId: sessionId, cwd: cwd, toolName: toolName)
let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601
guard var data = try? encoder.encode(event) else { exit(0) }
data.append(10)

let fd = socket(AF_UNIX, SOCK_STREAM, 0)
guard fd >= 0 else { exit(0) }
defer { close(fd) }
var address = sockaddr_un()
address.sun_family = sa_family_t(AF_UNIX)
withUnsafeMutableBytes(of: &address.sun_path) { bytes in
    _ = socketPath.utf8.withContiguousStorageIfAvailable { path in
        let count = min(path.count, bytes.count - 1)
        bytes.copyBytes(from: path.prefix(count))
        return count
    }
}
let length = socklen_t(MemoryLayout<sockaddr_un>.size)
let result = withUnsafePointer(to: &address) { ptr in
    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, length) }
}
guard result == 0 else { exit(0) } // fail-open: Pets is optional
data.withUnsafeBytes { _ = write(fd, $0.baseAddress, data.count) }
exit(0)

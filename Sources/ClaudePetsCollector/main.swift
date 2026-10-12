import Foundation
import ClaudePetsCore

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

let socketPath = CommandLine.arguments.dropFirst().first ?? "/tmp/claude-pets.sock"
let store = SessionStore()
unlink(socketPath)
let server = socket(AF_UNIX, SOCK_STREAM, 0)
guard server >= 0 else { fatalError("cannot create Unix socket") }
defer { close(server); unlink(socketPath) }

var address = sockaddr_un()
address.sun_family = sa_family_t(AF_UNIX)
withUnsafeMutableBytes(of: &address.sun_path) { bytes in
    _ = socketPath.utf8.withContiguousStorageIfAvailable { path in
        let count = min(path.count, bytes.count - 1)
        bytes.copyBytes(from: path.prefix(count))
        return count
    }
}
let addressLength = socklen_t(MemoryLayout<sockaddr_un>.size)
let bound = withUnsafePointer(to: &address) { ptr in
    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(server, $0, addressLength) }
}
guard bound == 0, listen(server, 8) == 0 else { fatalError("cannot bind or listen on \(socketPath)") }
chmod(socketPath, 0o600)
print("Claude Pets Collector listening on \(socketPath)")
fflush(stdout)

while true {
    let client = accept(server, nil, nil)
    guard client >= 0 else { continue }
    DispatchQueue.global(qos: .utility).async {
        var buffer = [UInt8](repeating: 0, count: 8192)
        var pending = Data()
        while true {
            let count = read(client, &buffer, buffer.count)
            if count <= 0 { break }
            pending.append(contentsOf: buffer[0..<count])
            while let newline = pending.firstIndex(of: 10) {
                let line = pending.prefix(upTo: newline)
                pending.removeSubrange(...newline)
                if let session = store.apply(line: Data(line)) {
                    print("[\(session.projectName)] \(session.state.rawValue)")
                    fflush(stdout)
                }
            }
        }
        close(client)
    }
}

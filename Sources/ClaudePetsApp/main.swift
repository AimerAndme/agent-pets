import SwiftUI
import Foundation
import ClaudePetsCore
import AppKit

#if canImport(Darwin)
import Darwin
#endif

final class PetAppState: ObservableObject {
    @Published private(set) var sessions: [ClaudeSession] = []
    @Published var selectedId: String?
    @Published var socketStatus = "启动中"

    private let store = SessionStore()
    private var serverFD: Int32 = -1
    private let socketPath = "/tmp/claude-pets.sock"

    func start() {
        #if canImport(Darwin)
        unlink(socketPath)
        serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else { socketStatus = "Socket 创建失败"; return }
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
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(serverFD, $0, length) }
        }
        guard result == 0, listen(serverFD, 8) == 0 else { socketStatus = "Socket 绑定失败"; return }
        chmod(socketPath, 0o600)
        socketStatus = "运行中"
        DispatchQueue.global(qos: .utility).async { [weak self] in self?.acceptLoop() }
        #else
        socketStatus = "仅支持 macOS"
        #endif
    }

    func stop() {
        #if canImport(Darwin)
        if serverFD >= 0 { close(serverFD); serverFD = -1 }
        unlink(socketPath)
        #endif
    }

    var selected: ClaudeSession? { sessions.first { $0.id == selectedId } ?? sessions.first }

    private func acceptLoop() {
        #if canImport(Darwin)
        while serverFD >= 0 {
            let client = accept(serverFD, nil, nil)
            guard client >= 0 else { continue }
            DispatchQueue.global(qos: .utility).async { [weak self] in
                var buffer = [UInt8](repeating: 0, count: 8192)
                var pending = Data()
                while true {
                    let count = read(client, &buffer, buffer.count)
                    if count <= 0 { break }
                    pending.append(contentsOf: buffer[0..<count])
                    while let newline = pending.firstIndex(of: 10) {
                        let line = pending.prefix(upTo: newline)
                        pending.removeSubrange(...newline)
                        if let session = self?.store.apply(line: Data(line)) {
                            Task { @MainActor in
                                self?.sessions = self?.store.sessions.values.sorted { $0.lastEventAt > $1.lastEventAt } ?? []
                                self?.selectedId = self?.selectedId ?? session.id
                            }
                        }
                    }
                }
                close(client)
            }
        }
        #endif
    }
}

struct ContentView: View {
    @ObservedObject var state: PetAppState

    var body: some View {
        HStack(spacing: 18) {
            PetStatusView(session: state.selected)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Claude Sessions").font(.headline)
                if state.sessions.isEmpty {
                    Text("等待 Claude Code 会话…").foregroundStyle(.secondary)
                } else {
                    ForEach(state.sessions) { session in
                        Button {
                            state.selectedId = session.id
                        } label: {
                            HStack {
                                Circle().fill(session.needsAttention ? .red : .green).frame(width: 8, height: 8)
                                VStack(alignment: .leading) {
                                    Text(session.projectName).lineLimit(1)
                                    Text(session.state.rawValue).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }.buttonStyle(.plain)
                    }
                }
                Text("Socket: \(state.socketStatus)").font(.caption2).foregroundStyle(.secondary)
            }.frame(minWidth: 220)
        }.padding(20).frame(minWidth: 500, minHeight: 220)
    }
}

struct PetStatusView: View {
    let session: ClaudeSession?
    var body: some View {
        VStack(spacing: 10) {
            Text(symbol).font(.system(size: 58))
            Text(session?.projectName ?? "Claude Pets").font(.headline)
            Text(session?.state.rawValue ?? "待机").foregroundStyle(.secondary)
            if let tool = session?.currentTool { Text(tool).font(.caption).foregroundStyle(.secondary) }
        }.frame(width: 180)
    }
    private var symbol: String {
        switch session?.state {
        case .waitingPermission, .waitingInput: return "🙋"
        case .error: return "😵"
        case .coding: return "⌨️"
        case .reading: return "🔎"
        case .running: return "⚙️"
        case .thinking: return "💭"
        case .completed: return "🎉"
        default: return "😴"
        }
    }
}

@main
struct ClaudePetsApp: App {
    @StateObject private var state = PetAppState()
    var body: some Scene {
        MenuBarExtra("Claude Pets", systemImage: "pawprint.fill") {
            Button("打开会话面板") { NSApp.activate(ignoringOtherApps: true) }
            Divider()
            Text("Socket: \(state.socketStatus)")
            Button("退出") { state.stop(); NSApp.terminate(nil) }
        }
        WindowGroup("Claude Pets") {
            ContentView(state: state).onAppear { state.start() }
        }
        .defaultSize(width: 560, height: 260)
        .commands { CommandGroup(replacing: .appInfo) {} }
        .onChange(of: state.socketStatus) { _, _ in }
    }
    init() { }
}

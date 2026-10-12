# Claude Pets 技术设计文档

版本：`v0.1-draft`

状态：当前版本设计基线

目标平台：macOS

## 1. 项目目标

Claude Pets 是一个 macOS 桌面宠物，用于展示 Claude Code 当前会话的运行状态，并提供多会话列表。

首版定位为“观察与提醒工具”，不直接控制 Claude Code，不读取完整 Prompt、模型回复或文件内容。

核心目标：

- 追踪单个 Claude Code 会话的当前状态；
- 展示多个 Claude Code 会话及其状态；
- 在等待授权、输入、错误和完成时提醒用户；
- Claude Pets 未启动、退出或崩溃时，不影响 Claude Code 正常执行；
- 只通过 Claude Code 官方 Hooks 接收生命周期事件。

## 2. 非目标

当前版本不包含：

- 精确的任务百分比预测；
- 从宠物直接批准 Claude Code 权限；
- 从宠物向 Claude Code 发送 Prompt；
- 读取并总结完整会话正文；
- 云同步和远程会话；
- 多只完整宠物同时显示；
- 对其他 Coding Agent 的通用适配。

## 3. 总体架构

```text
Claude Code
    │
    │ Official Hooks
    ▼
Hook Adapter
    │
    │ Unix Domain Socket + JSON Lines
    ▼
Pets Collector
    │
    ├── 事件校验与去重
    ├── 按 session_id 路由
    ├── 会话状态归约
    ├── 心跳与过期检测
    └── 多会话聚合
            │
            ▼
macOS Pet App
    ├── 桌面透明宠物窗口
    ├── 当前会话动画
    ├── 多会话列表
    ├── 菜单栏入口
    └── 系统通知
```

## 4. Claude Code Hook 集成

Claude Code Hooks 在生命周期事件发生时被调用。命令 Hook 从 stdin 接收 JSON 事件。首版使用命令 Hook，Hook Adapter 将事件发送到本地 Pets Collector。

重点事件：

| 事件 | 作用 |
| --- | --- |
| `SessionStart` | 创建或恢复会话 |
| `UserPromptSubmit` | 用户提交请求，进入思考状态 |
| `PreToolUse` | 工具即将执行 |
| `PostToolUse` | 工具执行成功 |
| `PostToolUseFailure` | 工具执行失败 |
| `PermissionRequest` | Claude 等待用户授权 |
| `Notification` | 等待输入、完成等通知 |
| `TaskCreated` | 创建任务 |
| `TaskCompleted` | 完成任务 |
| `SubagentStart` | 启动子 Agent |
| `SubagentStop` | 子 Agent 结束 |
| `Stop` | 当前响应结束 |
| `StopFailure` | 当前响应因错误结束 |
| `SessionEnd` | 会话结束 |

Hook 只用于上报状态，不参与 Claude Code 的权限决策。

## 5. Pets 未启动时的行为

这是系统的强制安全约束：

> Claude Pets 是可选观察器。Pets 未启动、不可达、崩溃或升级时，Hooks 必须 fail-open、快速返回，并对 Claude Code 的执行行为零影响。

Hook Adapter 的处理逻辑：

```text
读取 stdin 事件
    ↓
尝试连接 Unix Domain Socket
    ├── 连接失败：立即 exit 0
    └── 连接成功：发送事件，然后 exit 0
```

必须满足：

- Collector 不可达时返回码为 `0`；
- 不返回 deny、block 或其他权限决策；
- 不持续重试；
- 不等待 Pets 启动；
- 不将连接失败打印到 Claude Code 用户界面；
- 单次发送设置很短的超时时间；
- Hook 上报失败不能导致 Claude Code 任务失败。

不建议在 Pets 退出时动态删除 Claude Code 配置。保留 Hook 配置，由 Adapter 在运行时自动静默失效，避免配置竞态和损坏。

## 6. 本地通信协议

### 6.1 当前版本：Unix Domain Socket + JSON Lines

Socket 路径建议：

```text
/tmp/claude-pets.sock
```

JSON Lines 是每行一个完整 JSON 对象。每个 Hook 事件对应一行：

```text
{"event_id":"evt-123","session_id":"sess-1","event_type":"PreToolUse","tool_name":"Edit"}\n
{"event_id":"evt-124","session_id":"sess-1","event_type":"PostToolUse","tool_name":"Edit"}\n
```

接收端按换行读取并逐行解析。单行解析失败只影响当前事件，不应导致 Collector 退出。

### 6.2 事件格式

```json
{
  "schema_version": 1,
  "event_id": "uuid",
  "event_type": "PreToolUse",
  "session_id": "session-id",
  "timestamp": "2026-10-12T10:20:30.000Z",
  "cwd": "/Users/me/project",
  "tool_name": "Edit",
  "agent_id": null,
  "agent_type": null,
  "metadata": {}
}
```

字段约束：

- `event_id` 用于去重；
- `session_id` 是会话唯一键；
- `event_type` 使用 Claude Code Hook 事件名；
- `cwd` 可用于推导项目名；
- `tool_name` 只在工具事件中存在；
- 不默认传输 Prompt、回复全文、文件内容和完整 Bash 输出；
- 未知字段必须被忽略，以兼容未来事件扩展。

### 6.3 后续演进：HTTP over Unix Socket

当需要标准请求响应、诊断接口或更丰富的协议语义时，升级为：

```text
Unix Domain Socket + HTTP/1.1
```

即通过同一个 Unix Socket 发送 `POST /events`，而不是同时维护 Unix Socket 探活和 TCP HTTP 两套通道。

首版不实现独立 TCP HTTP 服务，也不监听 `0.0.0.0`。

## 7. 会话状态模型

```swift
enum SessionState {
    case offline
    case ready
    case thinking
    case reading
    case coding
    case running
    case waitingPermission
    case waitingInput
    case subagents
    case completed
    case error
    case possiblyStale
    case ended
}
```

会话数据：

```swift
struct ClaudeSession: Identifiable, Codable {
    let id: String                 // session_id
    var projectPath: String?
    var projectName: String
    var startedAt: Date?
    var lastEventAt: Date
    var state: SessionState
    var currentActivity: String?
    var currentTool: String?
    var toolsUsed: Int
    var activeTasks: Int
    var completedTasks: Int
    var needsAttention: Bool
    var errorMessage: String?
    var isPinned: Bool
    var lifecycle: LifecycleState
}
```

必须使用 `session_id` 作为唯一键。同一个项目目录可以同时运行多个 Claude Code 会话，不能用 `cwd` 替代 `session_id`。

## 8. 状态归约规则

事件不直接操作动画，而是先通过状态归约器更新会话：

```text
Hook Event
    ↓
校验 event_id / session_id
    ↓
查找或创建 ClaudeSession
    ↓
SessionReducer 更新状态
    ↓
更新当前会话选择器和会话列表
    ↓
映射到宠物动画
```

推荐映射：

| 事件或工具 | 状态 |
| --- | --- |
| `SessionStart` | `ready` |
| `UserPromptSubmit` | `thinking` |
| `PreToolUse(Read|Glob|Grep)` | `reading` |
| `PreToolUse(Edit|Write)` | `coding` |
| `PreToolUse(Bash)` | `running` |
| `PostToolUse` | `thinking` |
| `PermissionRequest` | `waitingPermission` |
| 输入类 `Notification` | `waitingInput` |
| `SubagentStart` | `subagents` |
| `Stop` | `completed` |
| `PostToolUseFailure` / `StopFailure` | `error` |
| `SessionEnd` | `ended` |

`Stop` 表示当前响应结束，不等价于整个开发目标完成。UI 文案应使用“本轮完成”，而不是直接显示“项目已完成”。

## 9. 单会话与多会话

底层始终维护多会话，桌面宠物只是当前选中会话的可视化结果。

### 单会话追踪

- 默认只显示一只宠物；
- 用户可以固定某个 `session_id`；
- 未固定时跟随最近活跃会话；
- 当前会话显示项目名、状态、动作和运行时长；
- 会话完成后播放短暂完成动画，再回到待机。

### 多会话列表

列表显示：

- 项目名；
- 当前状态；
- 当前工具或动作；
- 会话运行时长；
- 最近活动时间；
- 是否需要用户操作；
- 子 Agent 和任务数量；
- 是否为当前宠物绑定会话。

会话提醒优先级：

```text
waiting_permission
    > waiting_input
    > error
    > running
    > thinking
    > completed
    > idle
```

高优先级会话可以在列表中置顶，但不能无条件抢占用户已经固定的宠物会话。

## 10. 会话过期与异常退出

不能只依赖 `SessionEnd`，因为终端或 Claude Code 可能被强制关闭。

建议默认策略：

- 30 秒无事件：仍显示运行中，但降低动画强度；
- 90 秒无事件：标记为 `possiblyStale`；
- 180 秒无事件：标记为 `unknown/offline`；
- 收到新事件后重新激活；
- 用户可以手动清理历史会话。

这些时长应在设置中可调整。

## 11. 事件顺序与去重

事件处理规则：

1. 已处理过的 `event_id` 直接丢弃；
2. 每个 `session_id` 独立排序；
3. 旧事件不能覆盖较新的终态；
4. `SessionEnd` 后到达的迟到事件只记录，不自动恢复运行状态；
5. Collector 重启后，内存状态恢复为 `unknown`，等待新的 `SessionStart` 或事件；
6. 未知事件类型记录诊断日志，但不得导致 Collector 退出。

## 12. macOS 技术选型

推荐技术栈：

- Swift 6；
- SwiftUI：设置页、会话列表和菜单栏；
- AppKit `NSPanel`：透明、无边框、置顶和拖动；
- SpriteKit：宠物逐帧动画和简单粒子效果；
- Swift Concurrency：事件流与状态更新；
- Unix Domain Socket：本地 Collector 通信；
- `UserNotifications`：权限、错误和完成提醒；
- XCTest：协议、状态归约和多会话测试。

不建议首版使用 Electron、Unity 或 Godot。项目只针对 macOS，原生方案更适合透明桌面窗口、菜单栏和系统通知。

## 13. 安全与隐私

- Socket 只允许当前用户本地访问；
- 不监听公网或局域网地址；
- 校验事件大小、字段长度和 `schema_version`；
- Hook 只上报观察数据，不接收控制指令；
- 默认不保存 Prompt、模型回复和代码内容；
- 项目路径默认仅显示目录名；
- 不使用终端屏幕抓取或进程输出解析；
- App 未启动时不写入错误、不改变 Claude Code 执行流程。

## 14. MVP 验收范围

首个可运行版本必须验证：

1. Pets 启动后可接收 `SessionStart` 和工具事件；
2. 单个会话状态能正确映射到宠物动画；
3. 多个会话能按 `session_id` 独立显示；
4. 用户可以切换和固定当前宠物会话；
5. Pets 未启动时 Claude Code Hook 静默退出；
6. Pets 退出或崩溃后 Claude Code 不被阻塞；
7. 重复事件不会重复更新状态；
8. 乱序和迟到事件不会覆盖已结束会话；
9. 会话长时间无事件时会进入 `possiblyStale`；
10. 不读取或持久化完整 Prompt、回复和代码内容。

## 15. 实施顺序

建议按以下顺序实现：

1. 定义事件 JSON Schema；
2. 实现 Unix Socket Collector；
3. 实现 Hook Adapter 的 fail-open 行为；
4. 用日志验证完整 Hook 事件链；
5. 实现多会话 Event Store 和状态归约器；
6. 实现会话列表和当前会话选择器；
7. 接入 Swift 宠物窗口；
8. 增加权限、错误和完成通知；
9. 增加异常退出、乱序、重复事件测试；
10. 评估是否需要 HTTP over Unix Socket。

在事件链和多会话状态模型验证完成前，不应优先投入复杂动画设计。

## 16. 设计决策摘要

| 决策 | 当前选择 |
| --- | --- |
| Claude Code 集成 | 官方 Hooks |
| Hook 类型 | 命令 Hook + 轻量 Adapter |
| 存活判断 | Unix Domain Socket 连接结果 |
| MVP 内容通信 | Unix Socket 上的 JSON Lines |
| 后续通信演进 | HTTP over Unix Domain Socket |
| Pets 未启动 | Hook fail-open、静默、快速退出 |
| 会话主键 | `session_id` |
| 桌面显示 | 单宠物 + 多会话列表 |
| 进度表达 | 状态、动作、时长；不伪造百分比 |
| macOS UI | SwiftUI + AppKit `NSPanel` |
| 动画 | SpriteKit |

# Claude Pets

Claude Code 的 macOS 桌面宠物原型。

当前实现已包含：

- Swift Package；
- Unix Domain Socket Collector；
- JSON Lines 事件协议；
- fail-open Hook Adapter；
- 单会话状态归约和多会话存储；
- 基础状态机测试。

设计文档：

- [技术设计](docs/TECHNICAL_DESIGN.md)
- [用户指南](USER_GUIDE.md)

## 本地运行

启动 Collector：

```bash
swift run claude-pets-collector
```

macOS 图形界面原型：

```bash
swift run claude-pets-app
```

图形界面原型会自行创建 Collector Socket，因此不要同时启动 `claude-pets-collector`；二者会竞争同一个 `/tmp/claude-pets.sock`。

默认监听：

```text
/tmp/claude-pets.sock
```

在另一个终端模拟发送一个 Hook 事件：

```bash
printf '%s\n' '{"hook_event_name":"SessionStart","session_id":"demo","cwd":"/tmp/demo"}' \\
  | swift run claude-pets-hook
```

发送工具事件：

```bash
printf '%s\n' '{"hook_event_name":"PreToolUse","session_id":"demo","cwd":"/tmp/demo","tool_name":"Edit"}' \\
  | swift run claude-pets-hook
```

Collector 会输出会话状态变化。

如果 Collector 没有启动，Hook Adapter 会连接失败并返回成功状态。这是设计要求：Claude Pets 不在线时不能影响 Claude Code。

运行测试：

```bash
swift test
```

## 接入真实 Claude Code

构建并安装 Hook Adapter：

```bash
sh scripts/install-hook.sh
```

脚本会把 Adapter 安装到：

```text
~/.claude-pets/bin/claude-pets-hook
```

它只会打印 Hook 配置，不会覆盖现有的 `~/.claude/settings.json`。请将脚本输出的 `hooks` 内容合并到该文件，然后启动 Collector：

```bash
swift run claude-pets-collector
```

卸载 Adapter：

```bash
sh scripts/uninstall-hook.sh
```

## 当前限制

当前已提供菜单栏和会话面板原型；透明悬浮桌面窗口、完整宠物动画、自动修改 Claude Code 配置和完整诊断页尚未实现。当前代码已支持手动接入真实 Claude Code Hooks，用于验证 Hook → Unix Socket → 状态归约这条核心链路。

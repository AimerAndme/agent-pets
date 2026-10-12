# Claude Pets 用户使用指南

版本：`v0.1-draft`

> 当前仓库已实现 Collector、Hook Adapter 和手动 Hook 配置接入；桌面 App 和动画层仍未实现。涉及桌面宠物窗口的内容仍属于目标使用方式。

## 1. Claude Pets 是什么

Claude Pets 是一个 macOS 桌面宠物，用来显示 Claude Code 的运行状态。

它可以：

- 显示当前 Claude Code 会话正在思考、读取、编辑或运行命令；
- 显示多个 Claude Code 会话；
- 提醒你处理权限请求或输入请求；
- 在一轮响应完成、失败或会话结束时改变状态；
- 在 Claude Pets 未启动时完全不影响 Claude Code。

它不会：

- 代替 Claude Code 执行命令；
- 自动批准权限请求；
- 读取并展示完整 Prompt 或模型回复；
- 提供可信的任务百分比预测。

## 2. 使用前提

需要准备：

- macOS；
- 已安装并能正常运行的 Claude Code；
- 一个可以启动 Claude Code 的项目目录；
- Claude Pets App（MVP 完成后提供）。

Claude Pets 通过 Claude Code Hooks 接收事件，不需要抓取终端屏幕，也不需要访问 Claude Code 的账号凭据。

## 3. 首次使用流程

### 3.1 启动 Claude Pets

启动 App 后，Claude Pets 会：

1. 创建本地 Unix Domain Socket；
2. 启动本地事件 Collector；
3. 注册当前运行状态；
4. 在菜单栏显示 Claude Pets 图标。

首版 Socket 路径为：

```text
/tmp/claude-pets.sock
```

用户不需要手动创建该文件。

### 3.2 安装 Claude Code Hooks

当前版本提供安装脚本，但脚本不会覆盖用户现有配置：

```bash
sh scripts/install-hook.sh
```

脚本会构建并安装 Hook Adapter，并打印需要合并到 `~/.claude/settings.json` 的配置。配置完成后，Claude Code 的生命周期事件会交给 Hook Adapter 处理。

建议安装范围：

- 用户级：所有项目都可以追踪；
- 项目级：只追踪当前项目；
- 插件级：由 Claude Pets 统一安装和升级。

推荐首版使用用户级或插件级配置，避免要求用户手动编辑多个项目的配置文件。

### 3.3 启动 Claude Code

进入项目目录并启动 Claude Code：

```bash
cd /path/to/project
claude
```

提交一个请求后，Claude Pets 应显示类似状态：

```text
思考中 → 读取项目 → 编辑代码 → 运行命令 → 本轮完成
```

## 4. 单会话使用

桌面上默认显示一只宠物，代表当前绑定的 Claude Code 会话。

可以执行以下操作：

- 拖动宠物改变位置；
- 点击宠物查看当前项目和动作；
- 点击“固定当前会话”绑定到指定 `session_id`；
- 取消固定后跟随最近活跃会话；
- 通过菜单栏打开会话列表。

如果当前会话等待权限，宠物会显示等待状态并触发提醒。宠物不会替用户批准权限。

## 5. 多会话使用

当多个 Claude Code 会话同时运行时，打开会话列表可以查看：

- 项目名；
- 当前状态；
- 当前工具或动作；
- 运行时长；
- 最近活动时间；
- 是否需要用户处理；
- 子 Agent 和任务数量。

会话列表的提醒优先级为：

```text
等待授权 > 等待输入 > 错误 > 运行中 > 思考中 > 已完成 > 空闲
```

高优先级会话会在列表中置顶，但不会强制抢占用户已经固定的桌面宠物会话。

## 6. 状态含义

| 状态 | 含义 |
| --- | --- |
| 待机 | 当前没有需要显示的活跃会话 |
| 思考中 | Claude 已收到请求，暂未调用工具 |
| 读取中 | 正在读取、搜索或分析项目 |
| 编码中 | 正在编辑或写入文件 |
| 运行中 | 正在执行 Bash、测试或构建命令 |
| 等待授权 | Claude Code 等待你允许某个操作 |
| 等待输入 | Claude Code 等待用户输入或回答 |
| 子 Agent | 当前会话正在运行子 Agent |
| 本轮完成 | 当前响应结束，不代表整个项目完成 |
| 错误 | 工具调用或当前响应出现错误 |
| 状态可能过期 | 一段时间没有收到事件，可能仍在运行或已异常退出 |
| 已结束 | Claude Code 会话已经结束 |

## 7. Pets 未启动时的行为

这是预期行为，不是错误。

如果 Claude Pets 没有启动、被退出、崩溃或正在升级：

- Claude Code 仍然可以正常使用；
- Hook Adapter 尝试连接本地 Unix Socket 失败后立即退出；
- 不阻塞 Claude Code；
- 不改变工具权限；
- 不显示 Hook 错误；
- 不持续重试或等待 Pets 启动。

因此，用户可以选择不启动 Claude Pets，而不会影响原有 Claude Code 工作流。

## 8. 关闭和重启

正常关闭 App：

1. 点击菜单栏图标；
2. 选择“退出 Claude Pets”。

退出后，已安装的 Hooks 可以继续保留。它们会因为 Unix Socket 不可连接而自动静默失效。

重新启动 App 后，Collector 会重新创建 Socket，后续 Claude Code 事件即可继续被追踪。

不建议用户手动删除 Claude Code 的 Hook 配置。若要停用集成，应使用 App 设置中的“停用 Claude Code 集成”。

## 9. 隐私说明

默认情况下，Claude Pets 只处理：

- Hook 事件类型；
- `session_id`；
- 项目目录名；
- 工具名称；
- 时间戳；
- 子 Agent 和任务计数。

默认不保存：

- 完整 Prompt；
- 模型回复全文；
- 文件内容；
- 完整 Bash 命令输出；
- Claude Code 账号凭据。

本地事件通信只使用 Unix Domain Socket，不监听公网或局域网地址。

## 10. 常见问题

### 宠物没有反应

按以下顺序检查：

1. Claude Pets App 是否正在运行；
2. `/tmp/claude-pets.sock` 是否存在并可连接；
3. Claude Code Hooks 是否已安装；
4. Claude Code 是否产生了新的事件；
5. 当前会话是否已经进入过期状态。

首版诊断页应显示：Socket 状态、Hook 配置状态、最近一次事件时间和最近一次解析错误。

### Claude Code 变慢了

正常情况下，Pets Hook 不应明显增加 Claude Code 延迟。

如果变慢，应先退出 Claude Pets 验证：

```text
退出 Pets → 重新执行 Claude Code 操作 → 比较执行速度
```

如果退出 Pets 后恢复，应检查 Hook Adapter 是否错误地进行了同步等待或重试。

### 关闭 Pets 后 Claude Code 是否还能用

可以。关闭 Pets 后 Hook 连接失败，Adapter 应直接返回成功状态，不参与 Claude Code 的执行流程。

### 为什么没有精确百分比

Claude Code 的一般工具调用过程不提供可靠的总任务量，因此 Pets 默认显示状态、动作和持续时间。只有当会话明确产生可计数任务时，才可能显示“已完成 3 项，共 5 项”。

### 为什么会话显示“状态可能过期”

长时间没有收到事件可能意味着：

- Claude 仍在等待模型响应；
- Claude 正在执行较长命令；
- 终端被关闭；
- Claude Code 或 Hook Adapter 异常退出。

此状态是保守提示，不等价于任务失败。

## 11. MVP 验证流程

在完整 App 完成前，可以按以下顺序验证核心链路：

1. 启动本地 Collector；
2. 确认 `/tmp/claude-pets.sock` 已创建；
3. 启动 Claude Code；
4. 提交一个简单请求；
5. 检查 Collector 是否收到 `SessionStart`、`PreToolUse`、`PostToolUse` 和 `Stop`；
6. 退出 Collector；
7. 再次执行 Claude Code 操作；
8. 确认 Claude Code 没有因 Hook 连接失败而阻塞或报错；
9. 同时启动两个项目，确认事件按 `session_id` 分离。

当前仓库已提供 Collector 和 Hook Adapter；macOS App 尚未提供，因此上述流程目前验证的是 Hook → Unix Socket → 状态归约链路。

## 12. 用户可见的产品原则

- 宠物是可选的，不是 Claude Code 的前置依赖；
- 状态提示优先于复杂动画；
- 等待用户处理的状态优先提醒；
- 不用虚假的百分比制造确定感；
- 不读取不必要的会话内容；
- 多会话情况下，用户始终知道宠物当前代表哪个会话。

# 多语言、Rust 工具化与跨平台路线评估

## 结论

当前 PowerShell + WinForms 版本适合作为 Windows 原型和个人工具；如果目标是可发布、可维护、多语言、跨平台的 Samsung T-Series 工具，长期技术栈应迁移到 Rust。

推荐路线是 **Rust Core + CLI first，Tauri GUI later**。不要立刻推翻现有 GUI。先把稳定、可测试、可跨平台的核心能力沉到 Rust，再让现有 PowerShell GUI 或未来 Tauri GUI 调用它。

## 百分制评估

| 维度 | PowerShell/WinForms | Rust CLI | Rust + Tauri GUI | 结论 |
|---|---:|---:|---:|---|
| Windows 日常拔插体验 | 82/100 | 72/100 | 92/100 | GUI 是日常产品主形态，CLI 是核心能力和调试入口。 |
| 系统控制可靠性 | 64/100 | 88/100 | 88/100 | Rust 更适合直接调用 CfgMgr32、SetupAPI、EventLog 等系统接口。 |
| 多语言能力 | 35/100 | 82/100 | 90/100 | 当前字符串硬编码；Fluent 可建立成熟语言包。 |
| 跨平台潜力 | 15/100 | 78/100 | 82/100 | PowerShell/WinForms 基本 Windows-only；Rust 可做 OS adapter。 |
| 构建和类型安全 | 45/100 | 92/100 | 88/100 | Rust 编译期检查更适合长期维护。 |
| 分发体验 | 45/100 | 86/100 | 80/100 | CLI 单文件分发强；Tauri GUI 产品体验更好但打包更复杂。 |
| 维护成本 | 65/100 | 84/100 | 76/100 | Rust core 值得投入；Tauri 不应早于 core 稳定。 |

综合评分：

- 当前项目作为个人 Windows 工具：82/100。
- 当前技术栈作为长期产品基础：58/100。
- Rust Core + CLI：86/100。
- Rust Core + Tauri GUI：88/100。
- 立即全量 Rust GUI 重写：70/100，不推荐。

## 技术决策

选择 Rust Core + CLI first。当前 PowerShell GUI 保留，不被替换。Rust 第一阶段只实现只读能力：

- `list`：识别 Samsung T 系列盘。
- `readiness`：输出日常拔插判断。
- `doctor`：输出只读诊断摘要。

危险操作暂不进入 Rust 第一阶段：不格式化、不停止服务、不弹出设备。

## 多语言方案

采用 Fluent `.ftl` 语言包：

- `locales/zh-CN/app.ftl`
- `locales/en-US/app.ftl`

核心规则：

- Rust core 返回结构化状态和 message key。
- CLI/GUI 根据 locale 渲染文字。
- 状态、按钮、错误、风险解释、下一步建议全部使用 key。
- ICU4X 未来仅用于日期、数字、列表等格式化。

## 跨平台策略

平台能力必须拆成 OS adapter。

Windows：

- 长期使用 CfgMgr32/SetupAPI 做安全弹出。
- Event Log、进程、卷信息作为 Windows 证据。
- 当前 Rust 第一阶段只读，不弹出。

macOS：

- 使用 Disk Arbitration API 或 `diskutil` fallback。
- 必须处理 whole disk，不只处理 partition。
- 阻塞分析可以先用 `lsof` fallback。

Linux：

- 优先 UDisks2 D-Bus。
- CLI fallback 为 `udisksctl unmount` 和 `udisksctl power-off`。
- 阻塞分析先用 `lsof`/`fuser`。

## 风险

- Rust Windows drive detection 如果完全原生实现成本较高，第一阶段允许 PowerShell metadata fallback。
- 过早做 Tauri 会增加 UI、打包和多平台测试负担。
- 安全弹出是高风险系统操作，必须等只读诊断稳定后再实现。
- 多语言不是简单翻译，必须从 key 和结构化推荐开始做。

## 下一步

第一阶段完成 Rust workspace、Fluent 语言包、只读 CLI 和单元测试。第二阶段再做 Windows CfgMgr32 安全弹出原型。第三阶段评估 Tauri GUI。

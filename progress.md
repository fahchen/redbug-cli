# Progress Log — redbug-cli

## 2026-06-09
- 设计阶段完成: docs/screens.md (7 屏, CONFIRMED), gap-scan 8 项已解。已 commit (758636f)。
- 进入正式开发。建 planning 文件: findings.md (musubi/redbug 调研 + 架构裁决), task_plan.md (4 切片=4 phase), progress.md。
- 架构裁决: 3 root stores (NodesRoot/PresetsRoot/SettingsRoot) + child NodeStore/SessionStore。
- 下一步: 待用户确认 phase 划分 → 开始 Phase 1。

## 2026-06-10
- Phase 1 完成。架构 (user 修正): ETS-backed — `Server.Config` GenServer 持有 ETS + 落盘, stores 直读 ETS + 订阅 PubSub; 远程节点交互走 GenServer。Child stores 推迟 P2 (P1 flat projection)。
- 服务端: Server.Schema.* (Limits/Rtp/Session/Node/Preset/Settings) + Server.Config (ETS+JSON 持久化, atom-safe) + 3 root stores + socket 接线。cookie 不进 wire。
- TUI: 重写 musubi.ts (3 roots) + App.tsx (S1 树 + modal 输入 + preset 选择克隆). 删旧 TraceStore PoC。
- 验证: mix compile clean; bun typecheck clean; 配置落盘 file 0600 / dir 0700, cookie stripped from wire / 落盘; reload 还原 nodes/sessions/presets/cookie; 全监督树启动 OK (alt port 4099, 4010 被既有 beam 占用未动)。
- 未自动验证: 交互式 TUI 键盘 (需真实终端手测)。
- musubi quirk: 单独跑 `mix compile.musubi_ts` 会清空 manifest → 空 Stores; 必须走完整 `mix compile`。
- 下一步: 用户手测 TUI (`elixir --name ... -S mix run` 起 server + `bun run` 起 TUI); 然后 Phase 2 (SessionStore + redbug)。

## 2026-06-10 (Phase 2-4)
- Phase 2 完成: `Server.Trace` facade + per-session `Server.Trace.Runner` GenServer (redbug 交互全在 Runner)。SessionRoot store: RTP CRUD/toggle + start/stop + applyRestart + clearEvents + saveAsPreset。live stream via PubSub。dirty 标记 (running 且 signature≠applied_sig)。event 生命周期: stop≠clear, restart 插分隔标记, Ctrl+L 清空。e2e `test/session_root_test.exs` 走完整 store 层, 对真实 target 节点 green。
- Phase 3 完成: SessionScreen 重写为 S2 事件屏 (列 ts/k/name/pid/mfa/info, kind 符号 ↓↑→← + 色), 客户端 sort(o)/filter(/ scope+高亮)/group(g)。详情右栏 (enter, j/k 滚动, ctrl+j/k 切事件, tab 聚焦)。z zoom, E 导出 elixir term 到 $EDITOR。后端 fmt_ts 加 .mmm。
- Phase 4 完成: PresetManager.tsx (S4 双栏 CRUD/toggle/limits/rename auto-persist) + SettingsScreen.tsx (S6 theme/sort cycle + 列开关 + limits + $EDITOR 只读)。App 重构为 Router (mount 3 roots, 渲染前 setTheme 实时切 theme, 路由 tree/session/presets/settings)。S1 `p`→presets `,`→settings。S7 help 扩展按屏分组。SessionScreen 接 settings (列可见性 + default_sort 初值 + Ctrl+W saveAsPreset)。
- 验证: bun typecheck clean; mix compile --warnings-as-errors clean; e2e session_root_test green (target@127.0.0.1 起着)。
- 未自动验证: 交互式 TUI 键盘流程 (headless 无法驱动, 须真实终端手测)。
- 全 4 phase complete。

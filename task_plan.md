# Task Plan — redbug-cli 正式开发

源设计: `docs/screens.md` (7 屏, CONFIRMED)。技术调研: `findings.md`。
栈: Elixir musubi server (3 root stores + child stores) + opentui/React on Bun。

## Architecture (from findings.md)
- 3 root stores on one socket: `NodesRoot`, `PresetsRoot`, `SettingsRoot`。
- `NodesRoot` → `child(NodeStore, id: node_id)` per node → `child(SessionStore, id: session_id)` per session。
- `SessionStore` 持有 redbug 会话 + 事件 `stream`。
- Mutations = musubi `command`s。View ops (sort/filter/group) = 纯客户端。
- 配置持久化: `~/.redbug/config.json`, 文件权限 `0600` (cookie==RCE)。
- redbug 单例 per-target; 改 pattern 须 stop+start。

---

## Phase 1 — 骨架 + 配置 + S1 树 + preset clone
Status: complete

注: 架构改为 ETS-backed (per user) — `Server.Config` GenServer 持有 ETS, stores 直读 ETS + 订阅 PubSub, 远程节点交互走 GenServer 而非 store。Child NodeStore/SessionStore 推迟到 P2 (P1 用 flat projection)。

### Tasks
- [x] 定义 state 类型: Node/Session/RTP/Preset/Settings/Limits (`Server.Schema.*`, `use Musubi.State`). cookie 不进 wire (敏感)。
- [x] 配置持久化: `Server.Config` GenServer + ETS `:redbug_config`; `~/.redbug/config.json` 文件 0600 + 目录 0700; 启动加载, 变更落盘 + broadcast。atom-safe JSON 解析 (无 String.to_atom on input)。
- [x] 三 root store: NodesRoot / PresetsRoot / SettingsRoot (mount 订阅 + render + handle_command 转发 Config)。
- [~] child NodeStore / SessionStore: 推迟到 P2。
- [x] `use Musubi.Socket, roots: [NodesRoot, PresetsRoot, SettingsRoot]`。
- [x] S1 树视图 (opentui/React): node▸session 树, j/k 移动, n node, s session, e edit, c connect/disconnect, d delete, p presets, ? help, q quit。modal 输入用 `<input focused>`。
- [x] 新建 session 流程: node 上下文 + 名 + init-from(blank / preset 深克隆 traces 带新 id)。
- [x] commands: createNode/editNode/deleteNode, createSession(preset 克隆)/deleteSession, connect/disconnect。
- [x] 替换旧 PoC 单 root (TraceStore) 接线 (已删 TraceStore/TraceEvent)。

### Acceptance
- [x] TUI typecheck 通过; 服务端编译 + 全监督树启动 (Config+PubSub+Endpoint+distribution)。
- [x] 增删 node/session/preset 落盘 `~/.redbug/config.json` (文件 0600, 目录 0700); cookie 仅落盘不进 wire。
- [x] preset 克隆生成独立 session (traces 重新 gen_id, 无回指针)。
- [x] 重启恢复树快照 (reload 还原 nodes/sessions/presets/cookie)。
- [~] 交互式 TUI 键盘流程需真实终端手测 (headless 无法自动驱动)。

### 注意 (musubi 工具链 quirk)
- `mix compile.musubi_ts` **单独运行** 会清空 manifest (clean_outdated 把未 load 的模块条目删掉) → 生成空 `Stores {}`。必须走完整 `mix compile` (codegen 作为 pipeline 一环, 模块刚编译已 load)。

---

## Phase 2 — SessionStore + RTP + start/stop + live stream + 事件生命周期
Status: complete

注: 架构落地为 `Server.Trace` facade + per-session `Server.Trace.Runner` GenServer (redbug 交互全在 Runner, store 仅转发)。e2e 测试 `test/session_root_test.exs` 走完整 store 层验证 start→events→edit(dirty)→applyRestart(separator)→stop(retain)→clear(empty), 对真实 target 节点通过。
注 (musubi quirk): stream 内容 client-owned, `render/1` 返回 `%Musubi.Stream.Placeholder{}` 不可读 list; 测试事件内容须读物化源 (`Trace.snapshot/1`)。

### Tasks
- [ ] SessionStore 接 `:redbug`: start(Trc, Opts) 远程节点, stop(target_node)。
- [ ] RTP 增/删/改/开关 commands (item-level, Ctrl 触发, 无确认弹窗)。
- [ ] start/stop commands: start 自动连接 + 需 ≥1 enabled RTP; stop 异步。
- [ ] live 事件 stream: redbug 回调 → stream_insert(at:-1, limit:keep)。事件映射 to_event/1 (ts→ms, kind 符号)。
- [ ] Ctrl+S 应用并重启: 改 pattern → stop+wait_down+start。
- [ ] running-session 编辑模型: live-affecting edits(RTP 增删改开关, time/msgs) 置 `*`/`⚠ unapplied` 标记; rename/keep/列可见/theme 不触发。
- [ ] 事件生命周期: stop≠clear; restart 保留事件 + 插入 `── restarted HH:MM:SS ──` 分隔标记; Ctrl+L 清空 buffer。
- [ ] exit-while-dirty 提示: [Ctrl+S Apply&restart][enter Leave running][esc Cancel]。

### Acceptance
- 对远程节点真实 redbug 追踪, 事件实时进 stream 并在 TUI 渲染。
- 改 RTP → 标记 unapplied → Ctrl+S 重启生效。
- restart 保留旧事件 + 分隔标记; Ctrl+L 清空。

---

## Phase 3 — S2 视图层 + 详情
Status: complete

注: SessionScreen 重写为 S2 事件屏 (列 ts/k/name/pid/mfa/info, kind 符号 ↓↑→← + 色), 客户端 sort(o)/filter(/, scope+高亮)/group(g, pid/mfa/kind), 详情右栏(enter, j/k 滚动, ctrl+j/k 切事件, tab 聚焦, esc 关), z zoom, E 导出 elixir term 到 $EDITOR (renderer.suspend/resume + Bun.spawnSync), e 打开 S3 RTP 编辑 overlay。后端 `fmt_ts` 加 `.mmm`。TUI typecheck 通过; 键盘交互须真实终端手测。

### Tasks
- [ ] S2 事件列表: 列 ts(12,ms,锁) · k(1,符号+色,锁) · name(flex,注册名,`-`) · pid(9) · mfa(flex) · info(自适应,截断)。后 4 列 Settings 可开关。
- [ ] kind 符号集 E: ↓call(cyan) ↑retn(green) →send(yellow) ←recv(purple)。
- [ ] sort (o, 浮动 dropdown), filter (/, scope mfa/pid/info/all, 高亮匹配子串于目标列), group (g, by pid/mfa/kind) — 纯客户端。
- [ ] 详情右栏 (enter 显示): kind/ts/pid/name/init/mfa/payload/stack; j/k 滚动, ctrl+j/k 切上/下事件(可见序), tab 聚焦, esc 关。
- [ ] z zoom overlay; E 在 $EDITOR 以 elixir term 打开 (row + detail focus 均可用)。

### Acceptance
- sort/filter/group 即时生效无服务端往返; filter 高亮命中。
- enter 展开详情, ctrl+j/k 切事件, z zoom, E 打开 $EDITOR。

---

## Phase 4 — S4 preset / S5 node / S6 settings / S7 help
Status: complete

注: S4 `PresetManager.tsx` (双栏: preset 列表 + traces, CRUD/toggle/limits/rename, auto-persist 无 Ctrl+S, Ctrl+D 删 confirm)。S5 node 编辑沿用 S1 既有 modal (name+cookie, 级联删 confirm)。S6 `SettingsScreen.tsx` (theme/default_sort cycle + 4 列开关 + default_limits 编辑 + $EDITOR 只读, via updateSettings)。theme 10 个在 `theme.ts`, App `Router` 渲染前 `setTheme` 实时切换。S7 help 扩展为按屏分组 + kind 图例。SessionScreen 接 settings: 列可见性 + default_sort 初值 + Ctrl+W saveAsPreset。typecheck 通过, mix compile (--warnings-as-errors) 通过, e2e 仍 green。键盘交互须真实终端手测。

### Tasks
- [x] S4 Preset Manager: list/view-edit/new/delete; 存 traces+limits; inline rename; 自动落盘 (无 Ctrl+S)。
- [x] S5 Node Editor: name + cookie (沿用 S1 modal, 明文存储 文件 0600); 删 node 级联 sessions (确认)。
- [x] S6 Settings (key `,`): 列开关(name/pid/mfa/info 可开, ts/k 锁) + 全局默认 limits+sort + $EDITOR 只读显示 + theme。
- [x] theme: token 模型 + 首批 10 (theme.ts, P3 已落地)。
- [x] S7 Help (key `?`): kind 图例 + 按屏分组键位。

### Acceptance
- [x] preset CRUD 落盘 (Config 自动持久化); node 编辑/级联删除生效。
- [x] 列开关/全局默认/theme 切换即时生效并持久化 (setTheme 实时, updateSettings 落盘)。
- [x] ? S1 唤出 help (按屏分组覆盖全部屏)。
- [~] 交互键盘流程须真实终端手测 (headless 无法驱动)。

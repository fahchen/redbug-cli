# 会话 · 事件 Session · Events

单个会话的实时 trace 流。启停 trace、对行做 排序/过滤/分组、在任意事件上打开详情。
右上角 tab 切到 Console。

```
d                                         [ Events ] Console
┌──────────────────────── sort:ts↓ · filter:- · group:none ┐
│ ts    k  name    pid    mfa    info                       │
│ 12:13:47 ↑ :erlang.apply/2 <…>  Demo.tick/1  %{count:…}   │
│ 12:13:47 ↓ :erlang.apply/2 <…>  Demo.tick/1  [50356]      │
│ ...                                                       │
└───────────────────────────────────────────────────────────┘
 ▁▂▃  8/500   j/k move · enter detail · t traces · ⇧S/X run/stop · ? help · esc back
```

- 会话名（左）+ `Events / Console` tab（右）在框外顶部：选中 tab 用 bg 块 + 亮文字高亮，
  无分隔符。
- 事件区是带框 box；**没有 `events·N` 标题**（tab 已表明是 Events）。
- 排序/过滤/分组 meta 在**上边框线右对齐**（连接中/报错时染色 + 提示）。
  detail 面板打开时这三个 meta 隐藏，避免挤窄后溢出。
- 密集列表放在 `<scrollbox>` 里；重复项置灰（ditto），让视线跟着变化走。
- 底部统计是一个块：`sparkline  N/keep`（状态图在前、数量在后，无 label），颜色低调。
- `enter` 打开右侧详情面板（DetailMeta 用 chip：kind/ts/pid/name/mfa）；payload 用 `<code>`
  做 Elixir 高亮。
- 列显隐（name/pid/mfa/info）在 Settings（`,`）里开关，`ts`/`k` 常显。

## 状态机（连接 + trace + limit 整合成一条主状态线）

左下一个 statChip，一 glyph 一状态；右侧 hint 动态标注 `Space` 当前语意。
**`Space` = 唯一 go 键（永不破坏）**，`x` = stop（破坏性、独立键），`⌃S` = apply。

| 状态 | 左下 statChip | Space | 右侧 hint |
|------|--------------|-------|----------|
| connecting | `▌ connecting…`（黄） | —（等） | — |
| unreachable | `✖ can't reach node`（红） | retry | `space retry` |
| idle | `◇ idle`（灰） | start | `space start` |
| running | `● ▁▂▃ 8/500`（绿 + sparkline + 计数） | —（已跑，用 `x` 停） | `x stop` |
| running + unapplied | `● ▁▂▃ 8/500  ⚠ unapplied` | — | `x stop · ⌃S apply` |
| ended | `⧗ time limit (900s)` / `⧗ msgs limit (10000)`（黄） | restart | `space restart` |

- **idle vs ended**：idle = 没跑 / 手动 `x` 停了；ended = 跑满 time/msgs 上限自停（终态，Space 重启）。
  `keep` 只是缓冲上限，**不停** trace。
- **connect vs start**：connect（节点级）自动按需（Space 连不上先连再跑）；start（trace 级）由用户 Space 触发。用户只管 Space。
- 离开 running 时弹「Stop trace and leave?」确认（y = 停并离开；离开即 `Trace.stop`）。

detail 打开（右侧详情，meta 隐藏）：

```
┌───────────────────────────────────┐┌ Detail ───────────────┐
│ 12:13 ↓ :erlang.apply/2 … [48997] ││ Kind ↓call  Ts 11:55… │
│ ...                               ││ Pid  <…>  Name :erl…  │
│                                   ││ args                  │
│                                   ││ [48997]               │
└───────────────────────────────────┘└───────────────────────┘
```

## 弹层（frameless + 压暗背景；sort/filter/preset 用 `<select>`，trace 用手写 list）

| 键 | 弹层 |
|-----|---------|
| o | 排序（ts/kind/pid/mfa，升/降） |
| / | 过滤 —— scope `<select>` + query 输入框（Tab 切焦点） |
| t | trace/RTP 编辑器 —— 一级列表（开关/选中/删）；n/e 进二级新建·编辑页 |
| l | 会话上限 limits |

排序（`o`）：

```
Sort by
▶ ts ↓ desc
  ts ↑ asc
  kind ↑ asc
  …
j/k move · Enter apply · Esc cancel
```

过滤（`/`）：

```
Filter events
scope
▶ all
  mfa
  pid
  info
query
[ _ ]
Tab switch scope/query · Enter apply · Esc cancel
```

trace/RTP 编辑器（`t`）—— 两级页面。

一级：trace 列表（选中/开关/删）。说明只留一行，不塞例子：

```
Traces
[x] Demo.tick/1 -> return          ← 高亮行 = 选中（手写 list，无 ▶ 标记）
n new · e edit · d del · space toggle · ⌃W save preset · esc close
```

二级（`n` 新建 / `e` 编辑）：整页替换一级 list，input 在上、RTP 例子做参考。
`esc` 回一级 list（非关闭），`enter` 保存回 list。edit 预填现有 pattern：

```
New RTP:                           ← edit 时为 "Edit RTP:" + 预填
[ redbug spec, e.g. lists:seq/2 -> return ]
Enter ok · Esc cancel

Common RTP rules (Elixir)
Enum.map/2 -> return             call args + return value
MyMod.func -> return;stack       + call stack
Demo.tick when '$1' > 100 -> return   guard on 1st arg
Enum.map/2  ·  MyMod._  ·  MyMod   arity · any fun · whole module
```

会话上限（`l`）：

```
Session limits
keep time msgs (space-separated)
[ 500 900 10000 ]
Enter apply (Ctrl+S to restart if running) · Esc cancel
```

## 按键

| 键 | 动作 |
|-----|--------|
| j/k | 移动 · enter 详情 |
| space | 上下文 go：retry / start / restart（永不破坏；自动按需 connect） |
| x | stop（停 trace，破坏性、独立键） |
| ⌃S | apply（改了 RTP 后重启生效） |
| t | 编辑 traces（RTP）· l 会话上限 |
| [ / ] | 切换 Events ⇄ Console（`<tab-select>` 头，受控 ref 同步） |
| z | 放大详情 · v 导出到 $EDITOR |
| esc | 关详情 / 返回（running 时弹确认「Stop trace and leave?」） |

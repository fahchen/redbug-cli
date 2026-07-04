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

## 不同状态

空态（还没启动 trace）：

```
d                                         [ Events ] Console
┌──────────────────────── sort:ts↓ · filter:- · group:none ┐
│ ts    k  name    pid    mfa    info                       │
│ No events yet · ⇧S to start                               │
└───────────────────────────────────────────────────────────┘
 0/500   j/k move · enter detail · ⇧S/X run/stop · ? help · esc back
```

运行中（有事件、sparkline 走动）：

```
┌──────────────────────── sort:ts↓ · filter:- · group:none ┐
│ 12:13:47 ↑ :erlang.apply/2 <…> Demo.tick/1  %{count:…}    │
│ 12:13:47 ↓ :erlang.apply/2 <…> Demo.tick/1  [50356]       │
└───────────────────────────────────────────────────────────┘
 ▁▂▃  8/500   …
```

detail 打开（右侧详情，meta 隐藏）：

```
┌───────────────────────────────────┐┌ detail ───────────────┐
│ 12:13 ↓ :erlang.apply/2 … [48997] ││ kind ↓call  ts 11:55… │
│ ...                               ││ pid  <…>  name :erl…  │
│                                   ││ args                  │
│                                   ││ [48997]               │
└───────────────────────────────────┘└───────────────────────┘
```

连接中 / 报错（状态在**左下角**，与 events 计数互斥：连上显计数、异常显状态）：

```
连接中：  ▌ connecting…                        （黄）
报错：    ✖ Can't reach node — check … · c retry （红）
连上后：  ▁▂▃  8/500                            （dim，计数 + sparkline）
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
| ⇧S / ⇧X | 启动 / 停止 trace |
| [ / ] | 切换 Events ⇄ Console（`<tab-select>` 头，focus 时收键） |
| z | 放大详情 · v 导出到 $EDITOR |
| esc | 关详情 / 返回 |

# 会话 · 事件 Session · Events

单个会话的实时 trace 流。启停 trace、对行做 排序/过滤/分组、在任意事件上打开详情。
右上角 tab 切到 Console。

```
d                                                    Events  Console
┌ events · 0 ────────────────────────┐
│              sort:ts↓ · filter:- · group:none      │
│ ts    k  name    pid    mfa    info                │
│ No events yet · ⇧S to start                        │
│                                                    │
└────────────────────────────────────────────────────┘
 0 · 0/500   j/k move · enter detail · t traces · ⇧S/X run/stop · ? help · esc back
```

- 会话名 + `Events / Console` tab 在框外顶部；事件区是带框 box，
  标题 `events · N` 在上边框线（连接中/报错时染色 + 提示）。
- 框内右上角为 排序/过滤/分组 meta。
- 密集列表放在 `<scrollbox>` 里；重复项置灰（ditto），让视线跟着变化走。
- `enter` 打开右侧详情面板；payload 用 `<code>` 做 Elixir 高亮。

## 弹层（全部 `<select>` / 输入框）

| 键 | 弹层 |
|-----|---------|
| o | 排序（ts/kind/pid/mfa，升/降） |
| / | 过滤 —— scope `<select>` + query 输入框（Tab 切焦点） |
| t | trace/RTP 编辑器 —— `[x]` 开关、增/改/删 |
| l | 会话上限 limits |

## 按键

| 键 | 动作 |
|-----|--------|
| j/k | 移动 · enter 详情 |
| ⇧S / ⇧X | 启动 / 停止 trace |
| ⇧H / ⇧L | 切换 Events ⇄ Console |
| z | 放大详情 · v 导出到 $EDITOR |
| esc | 关详情 / 返回 |

# 会话 · 控制台 Session · Console

针对会话目标节点的 Elixir/Erlang 代码执行器。不是 REPL：每次运行是在 `$EDITOR` 里
写好的整段代码，结果进服务端持久化的历史。右上角 tab 切回 Events。

```
d                                                    Events  Console
┌ console · 0 ─────────┐┌ ✓ sup-tree · ok · 12ms ────────────┐
│  ⟳ 10:02 sup-tree    ││ code                               │
│  ✓ 10:01 proc-count  ││ :supervisor.which_children(Sup)    │
│  ✗ 10:00 ets-info    ││ result                             │
│                      ││ [{Worker, #PID<0.5.0>, :worker}]   │
└──────────────────────┘└────────────────────────────────────┘
 0 runs   j/k move · n new · r run · s stop · ? help · esc back
```

- 会话名 + tab 在框外顶部。两栏各带框：左 `console · N` 历史（`<scrollbox>`），
  右 = 选中执行，标题在上边框线（状态字形 + 名字 + 状态 + 耗时）。
- 历史每行一个状态字形 + 时间 + 标签；右栏代码 + 结果用 `<code>` Elixir 高亮。
- `n` 弹出 snippet `<select>`（`(blank)` + 库）→ 在 `$EDITOR` 里编写 → 运行。

## 按键

| 键 | 动作 |
|-----|--------|
| j/k | 移动 |
| n | 新建执行（选 snippet → $EDITOR） |
| e | 编辑选中并重跑 |
| r | 原样重跑 · v 在 $EDITOR 里查看 |
| s | 停止运行中（需确认） · c 清空历史（需确认） |
| ⇧H / ⇧L | 切换 Events ⇄ Console |
| esc | 返回 |

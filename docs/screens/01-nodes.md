# 节点 Nodes

根屏幕。左侧节点列表，右侧当前节点的会话。
用于管理连接目标、连接/断开、进入某个会话查看 trace。

```
┌ nodes ──────────────┐┌ target@127.0.0.1 ───────────┐
│                     ││ host    127.0.0.1           │
│  target@127.0.0.1 1 ││ cookie  rb••••st            │
│  app@127.0.0.1    0 ││                             │
│  muku@178         1 ││   d   stopped               │
│                     ││                             │
└─────────────────────┘└─────────────────────────────┘
 0/3 connected   j/k node · enter sessions · n new · c connect · ? help · q quit
```

右栏顶部是节点 detail（当前用单行内联；host / cookie / ssh / source）：

- host：直连节点取 `name@host` 的 host；SSH 节点取 `ssh_host`。
- cookie：中间 redact，只留头 2 尾 2（RCE 凭证不明文），如 `rb••••st`。
- ssh：仅 SSH 节点，`user@host · container`。
- source：仅来自环境变量的只读节点。

## 右栏状态

直连节点、有会话：

```
┌ target@127.0.0.1 ─────────────────────────┐
│ host 127.0.0.1  ·  cookie rb••••st        │
│                                           │
│   d   stopped                             │
└───────────────────────────────────────────┘
```

SSH 节点、空会话：

```
┌ app@127.0.0.1 ────────────────────────────────────────────┐
│ host 192.168.139.221 · cookie s3••••et · ssh fahchen@… · demo │
│                                                            │
│ No sessions · s to add                                     │
└────────────────────────────────────────────────────────────┘
```

连接报错（detail 后补红色错误 + 重试）：

```
┌ target@127.0.0.1 ─────────────────────────────────────┐
│ host 127.0.0.1 · cookie rb••••st  ·  ✖ nodedown · c retry │
│   d   stopped                                         │
└───────────────────────────────────────────────────────┘
```

## 说明

- 两栏各是带框 box，标题落在上边框线（单线框）：左 `nodes`，右 = 节点名。
- 有焦点的一栏边框 + 标题变亮（primary/borderActive），另一栏置灰。
- 节点行：`名字`（左）+ 会话数（右对齐到框内右缘）。状态点只在异常时出现
  （连接中 = 盲文 spinner，错误 = 红 ✖）；已连接 = 绿 ●，空闲保持安静。
- 右栏会话每行带 1 起的编号（`1 名字`）：直接按数字跳转，连续按可到两位数以上；
  超过最大 → 最后一项；`k`/↑ 在首项继续上导 → 回到最后一项。
- 四个方向 padding 统一（`padding=1`）。
- 底部 statusbar 无框、无独立底色，直接融进页面背景。
- 所有 modal 无边框：压暗遮罩（0.78）+ 面板底色，焦点集中在 modal。

## 节点连接状态

节点行左侧的状态点只在“非空闲”时出现（只暴露异常，已连接也给一个绿点确认）：

```
idle        target@127.0.0.1     无点（未连接，保持安静）
connecting  ⠋ target@127.0.0.1   盲文 spinner，轮播
connected   ● target@127.0.0.1   绿点（success）
error       ● muku@178           红点（error）
```

连接失败时，右栏 detail 后补一个红色 chip：`[✖][Can't reach node … · c retry]`，
`c` 手动重试。底部 statusbar 显示 `N/总 connected`。

## 节点编辑器（n 新建 / e 编辑）

无边框 modal，压暗背景。每个 input 的 label 在上（靠颜色标记焦点，无前缀符号），
placeholder 给一个示例值：

```
New node

name    [ myapp ]           ← 节点名和 host 拆成两个字段
host    [ 127.0.0.1 ]       ← 保存时拼回 name@host
port    [ (direct dist port) ]  ← 直连的 distribution 端口（可选）
cookie  [ secretcookie ]

over SSH (optional — leave blank to dial directly)
ssh host   [ prod-1.example.com ]
ssh port   [ 22 ]           ← SSH 端口（可选）
ssh user   [ deploy ]
container  [ myapp ]

Tab/Shift+Tab switch field · Enter save · Esc cancel
```

- `name` + `host` 拆开编辑，保存拼回 `name@host`（编辑已有节点时反向拆开）。
- 新增 `port`（直连 dist 端口）、`ssh port`。不加 ssh key（走 ssh-agent/默认 key）。
- port/ssh_port 已持久化到 config；连接时使用这两个端口的 dial 逻辑是后端后续。

## 会话编辑器（s 新建会话）

先取名，再选“从哪个预设初始化”：

```
New session
name  [ my-trace ]

Session "my-trace" — init from
▸ (blank)
  hello-world
j/k move · Enter create · Esc cancel
```

## 按键

| 键 | 动作 |
|-----|--------|
| j/k | 移动 |
| enter | 焦点切到会话 → 打开会话 |
| n | 新建节点 |
| s | 在该节点新建会话 |
| c | 连接 / 断开 |
| e | 编辑节点 |
| d | 删除（需确认） |
| p | 预设 · `l` 片段库 · `,` 设置 · `?` 帮助 · `q` 退出 |

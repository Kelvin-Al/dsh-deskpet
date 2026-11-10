# DSH 桌宠 · 鲸鱼娘 🐋

挂在 Windows 桌面上的透明置顶小窗口，会跟着 DSH 的任务状态换表情，还能右键叫出功能面板、直接和小鲸聊天。

![四态](assets/pet/sheet.png)

## 启动 / 退出

- **启动**：双击 `launch.cmd`（单实例，重复双击不会叠出第二只）
- **退出**：右键 → `退出`
- **关机**：右键 → `关机`（会先确认，然后 5 秒后关机）；Windows 关机/注销时桌宠会收到 `WM_QUERYENDSESSION` / `WM_ENDSESSION`，先自己关掉再放行关机
- **移动**：按住左键拖动，松手后位置记进 `pet-window.json`
- **摸摸**：**双击角色**（点立绘外的透明区不算）→ 开心 15 秒后回待机
- **唤醒**：休眠时双击角色
- **功能面板**：**右键**（气泡窗形式，贴着头顶弹出）
- **聊天**：右键 → `和小鲸聊天`

## 四个状态

| 状态 | 立绘 | 什么时候出现 |
| --- | --- | --- |
| 待机 idle | `assets/pet/idle.png` | 默认；没有 DSH 任务在跑 |
| 工作 busy | `assets/pet/busy.png` | 有 DSH 任务在跑（会话 `turnOpen`） |
| 开心 happy | `assets/pet/happy.png` | 双击摸摸（15s）；或任务完成（30s，同时弹气泡） |
| 休眠 sleepy | `assets/pet/sleepy.png` | 待机连续 3 分钟 |

状态机规则：

- 任务完成时，无论当前什么状态都进开心 30 秒；已在开心则顺延 30 秒，气泡提示「有新完成任务」；
- 开心结束后：还有任务在跑就回工作，否则回待机；
- 只有待机满 3 分钟会睡；工作状态不会睡；休眠时来了新任务会自动醒；
- 双击只认角色身上的像素，透明区域点不到。

## 聊天框 `pet-chat.ps1`

右键 → `和小鲸聊天`，在宠物头顶弹出聊天框：上面是消息，下面是输入框，回车发送、Esc 关闭。

- 走的是 DSH 现在用的同一个网关（tokendance，OpenAI 兼容接口），用 `.dsh/.credentials.yaml` 里的 `TOKENDANCE_API_KEY`，**不占 DeepSeek 官方 API 的 token 余额**；
- 请求在后台 runspace 里跑，不会卡住桌宠动画；
- 如果 .NET 的 TLS 在当前环境拿不到凭据（受限进程里会报 `underlying connection was closed`），会自动改用 `chat-node.js`（Node 自带 OpenSSL）再发一次，日志里会记 `已改用 node`；
- 对话历史只存在内存里，关掉桌宠就没了；「清空」按钮重置上下文。

可选的配置项（不写就用默认值）：

```json
{
  "chatUrl":    "https://tokendance.space/gateway/v1/chat/completions",
  "chatModel":  "deepseek-v4.1-flash-1017",
  "chatKey":    "",                  // 不写就从 ~/.dsh/.credentials.yaml 读
  "chatSystem": "你是小鲸，一只住在 Windows 桌面上的 DeepSeek 桌宠……"
}
```

想换成官方 DeepSeek API（会消耗 token 额度），把 `chatUrl` 改成 `https://api.deepseek.com/chat/completions`，`chatModel` 改成 `deepseek-chat`，`chatKey` 填 `DEEPSEEK_API_KEY` 即可。

## 功能面板 `pet-actions.ps1`

右键宠物，在头顶拉出气泡面板（上方放不下会自动改到左/右/下）：

| 条目 | 做什么 |
| --- | --- |
| 打开 DSH | 把 DeepSeek Harness 窗口恢复到前台（没开就启动） |
| 和小鲸聊天 | 打开聊天框 |
| 截个屏 | 全屏截图存到 `shots\shot-时间戳.png` |
| 复制工作区路径 | 路径进剪贴板 |
| 说句话 | 随机台词 |
| 四处游动 | 开关屏幕游走，右侧显示状态 |
| 关机 | 确认后 5 秒关机；系统关机/注销时桌宠会自动先关掉自己 |
| 退出 | 关闭桌宠 |

加功能：在 `$script:actItems` 加一行，再在 `Invoke-PetAction` 补一个分支。

## 配置文件 `pet-config.json`

```json
{
  "name": "小鲸",
  "wander": false,          // 是否自己在屏幕上慢慢游走
  "bob": false,             // 上下漂浮（已关）
  "topmost": true,
  "scale": 1.0,
  "sprite": "assets/pet/idle.png",
  "spriteBusy": "assets/pet/busy.png",
  "spriteHappy": "assets/pet/happy.png",
  "spriteSleepy": "assets/pet/sleepy.png",
  "spriteHeight": 300,      // 立绘显示边长（四张同画布）
  "lines": ["..."]          // 「说句话」时随机挑一条
}
```

改完退出再双击 `launch.cmd` 生效。

## 让 DSH 对它说话 `pet-state.json`

```json
{
  "name": "小鲸",
  "message": "测试跑完啦，全绿 ✅",
  "updated": 1793088000000, // 毫秒时间戳，必须递增
  "duration": 8
}
```

立刻说一句：

```powershell
$p = 'C:\Users\admin\Documents\deepseek-harness\default-workspace\ds-pet\pet-state.json'
@{ message='喝口水吧'; updated=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(); duration=6 } |
  ConvertTo-Json | Set-Content $p -Encoding UTF8
```

状态由状态机自己管，`mood` 字段不再生效；这里只负责「让它说一句话」。

## 行为日志 `Log\pet.log`

桌宠会在工作区根目录建 `Log` 文件夹（即 `ds-pet` 的上一级），把「实际做了什么」一行一件记下来：

```
[02:25:01] 启动  小鲸启动，位置 (1893,345)
[02:25:01] 状态  检测到 DSH 任务，进入工作
[02:25:40] 任务  有新完成任务，进入开心 30 秒
[02:25:40] 说话  有新完成任务
[02:26:10] 状态  开心结束，回到工作
[02:27:00] 面板  打开功能面板
[02:27:02] 功能  截个屏
[02:28:00] 聊天  发送：在吗
[02:28:04] 聊天  回复：在的在的～
[02:32:00] 退出  桌宠关闭，位置 (1893,345)
```

- 一行一件事，超过 60 字自动截断；只记行为，不记调试细节；
- 排错用的技术日志仍在 `ds-pet\pet.log`；
- 写日志失败（权限/磁盘）不会影响桌宠运行。

## 换图 / 改图

- 现在的立绘在 `assets/pet/`（idle / busy / happy / sleepy + sheet.png），360×360 透明底；
- 生成流程：`_gen_v5.ps1` / `_gen_idle_ear.ps1` 调网关出图（**纯绿幕背景**）→ `_keygreen.py` 抠绿幕 + 去溢色 → 输出透明 PNG；
- 出图提示词里锁死了这几条，改图时别丢：
  - **没有人类耳朵**，头部两侧只有一片横向扇贝边的鲸鱼鳍耳；
  - 头发、鳍耳、鲸尾**同一套深藏蓝**（主色 `#2B3FA8`、高光 `#4D6BFE`、暗部 `#1B2A7A`）；
  - 长发到腰、发尾卷曲，头顶**只有呆毛**，白色荷叶边发带**不带蝴蝶结**；
  - 干活/睡觉两态必须有**白色四腿椅**，笔记本背面是**鲸鱼 logo**（不能出现任何水果标志）；
- 不再用白底 + 手动抠轮廓：白底图边缘抗锯齿会残留一圈白边，绿幕抠像 + 去溢色没有这个问题；
- 换图只要保持四张同画布、角色脚底对齐，气泡锚点会在启动时自动扫描头顶重新校准，不用改代码。

### 为什么用绿幕而不是「透明底参数」

网关的 `seedream-5.0-lite` 走 `openai:image-generations` 协议，传 `background: transparent`、`output_format: png` **仍返回无 alpha 的 RGB 图**（角落是 `253,253,253`）。
带原生透明输出的 `seedream-5.0-flash` 只支持 `ark:image-generations` 协议，当前网关的 OpenAI 兼容路由到不了。所以选绿幕 + 抠像这条稳定的路。

## 注意

- 需要 Windows PowerShell 5.1（系统自带）。
- `pet.ps1`、`pet-actions.ps1`、`pet-chat.ps1` 必须保存为 **UTF-8 带 BOM**，否则 PowerShell 5.1 会把中文读成乱码。

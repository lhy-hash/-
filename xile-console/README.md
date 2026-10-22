# 喜乐控台（Vue3 + Node + LiveTalking）

本地闭环：控台输入 → Ollama 生成口播 → LiveTalking（Wav2Lip）实时出镜 → OBS 手动采集推流。

旧 Flutter 工程（`ai_digital_live`）不改。数字人驱动仍是 `C:\dev\LiveTalking`，不使用 SadTalker。

## 端口

| 服务 | 地址 |
| --- | --- |
| LiveTalking | http://127.0.0.1:8010 |
| Node 调度 | http://127.0.0.1:8787 |
| Vue 控台 | http://127.0.0.1:5173 |
| Ollama | http://127.0.0.1:11434 （模型 `qwen2.5:7b`） |

## 启动顺序

1. **数字人引擎**（已有脚本，形象以 `.env` 为准）

```powershell
cd C:\dev\LiveTalking
powershell -ExecutionPolicy Bypass -File .\start_xile_engine.ps1
```

浏览器能打开 http://127.0.0.1:8010 即表示引擎就绪。

2. **Ollama**（可选。没开也能用「直接口播」念原文）

```powershell
ollama serve
ollama pull qwen2.5:7b
```

3. **控台**

```powershell
cd "c:\Users\86186\Desktop\喜乐\xile-console"
npm install
npm run dev
```

打开 http://127.0.0.1:5173 。右侧预览接通（出现人脸）后，在左侧输入内容，点「生成并口播」。

环境变量（可选）：

- `XILE_PORT` 默认 `8787`
- `XILE_LIVETALKING` 默认 `http://127.0.0.1:8010`
- `XILE_OLLAMA` 默认 `http://127.0.0.1:11434`
- `XILE_OLLAMA_MODEL` 默认 `qwen2.5:7b`
- `XILE_VOICE` 默认 `zh-CN-XiaomengNeural`

## 手机提问同步

1. 电脑保持 LiveTalking + `npm run dev`（Node 会轮询 `/api/xile/asks`）。
2. 手机安装观众端，引擎地址填 `http://电脑Wi‑Fi-IP:8010`，进入 **喜乐美食直播间**（`room_food`）。
3. 手机文字/语音提问 → 只上报到引擎，不在手机本地答。
4. Node 自动：Ollama 生成回答 → LiveTalking 口播（电脑预览/OBS）→ 写回公屏 → 手机同步看到回答。

控台可开关「手机提问自动答」，并可改房间 ID / 人设 / 货品背景。

## 口播怎么走

- 「只生成」：`POST /api/chat`，只调 Ollama，不驱动数字人。
- 「生成并口播」：`POST /api/chat_and_speak`。Ollama 失败或未启动时，用输入原文口播。
- 「直接口播」：`POST /api/speak`，原文送给 LiveTalking `POST /human`（`type=echo`，带 `tts.ref_file`）。
- 「打断」：`POST /api/interrupt` → LiveTalking `/interrupt_talk`。
- 预览 iframe 与控台不同源，读不到页面里的 session。Node 在 session 为空时请求 `GET /api/admin/sessions`，用最新会话。

状态通过 WebSocket `ws://127.0.0.1:8787/ws`（开发时由 Vite 代理 `/ws`）推到控台。

## OBS 手动推流

1. 打开 OBS，新建场景。
2. 来源选「窗口采集」对准控台浏览器，或「浏览器源」填 `http://127.0.0.1:8010/xile_preview.html`（只要数字人画面）。
3. 音频：桌面音频或浏览器音频，确认能听到口播。
4. 设置 → 推流：服务选自定义，填抖音 / 视频号给的服务器地址和串流密钥。
5. 点「开始推流」。本控台不会自动推流。

## 验收

- Ollama 开着：输入问题 → 口播稿变化 → 数字人开口。
- Ollama 关着：点「直接口播」或「生成并口播」仍能念原文。
- 「打断」能停当前句。
- OBS 能采到预览画面（人工看一次即可）。

## 第一期不做

弹幕抓取、SadTalker、OBS 自动推流、数据看板、多直播间并发、手机 Flutter 改造。

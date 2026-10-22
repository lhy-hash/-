# 喜乐 · 真实 AI 数字人直播部署说明（免费开源栈）

手机 App = 控台；真实嘴型+声音在 **GPU 电脑** 的 LiveTalking 上跑。

详细免费栈说明见：[FREE_STACK.md](./FREE_STACK.md) 与 `C:\dev\LiveTalking\XILE_README.md`

## 架构

```
观众(抖音/快手/B站)
    ↑ OBS RTMP（免费）
浏览器窗口捕获数字人画面
    ↑ WebRTC 预览 :8010
LiveTalking（Wav2Lip 嘴型 + Qwen TTS 真人声）
    ↑ /human 文本驱动
喜乐 App（手机控台）
```

## 1. 启动引擎

```powershell
powershell -ExecutionPolicy Bypass -File C:\dev\LiveTalking\start_xile_engine.ps1
powershell -ExecutionPolicy Bypass -File C:\dev\LiveTalking\start_xile_obs.ps1
```

- 预览：http://127.0.0.1:8010/index.html
- 手机引擎地址：`http://192.168.40.241:8010`（以当前电脑 Wi‑Fi IP 为准）
- Avatar：`wav2lip_avatar_female_model`
- 声音：通义 `Cherry`（国内可用）。Edge-TTS 常因微软节点不可达落到机械音，故不用作默认。

需在 `C:\dev\LiveTalking\.env` 配置 `DASHSCOPE_API_KEY`（或沿用 `.llm_secrets` 的 `LLM_API_KEY`）。

## 2. 手机喜乐 App

1. 设置 → 本地引擎 → 填电脑局域网 IP:8010  
2. Avatar ID 与引擎一致  
3. 检测引擎 → 进房；角标「真实数字人」后再开播  
4. 话术走引擎 `/human`，嘴型与声音同步  

## 3. OBS 推抖音/快手/B站

1. 浏览器打开引擎预览页  
2. OBS → 窗口捕获该浏览器  
3. 贴 Logo /「AI数字人」标识  
4. 设置 → 推流 → 自定义 RTMP + 串流密钥 → 开始推流  

可选虚拟摄像头：`start_xile_virtualcam.ps1`（需 OBS Virtual Camera + pyvirtualcam）

## 4. 换照片形象

- http://127.0.0.1:8010/avatar.html  
- 或 App 直播间上传照片  

## 5. MuseTalk / 3D（可选）

- MuseTalk：代码已在仓库，需另下权重后 `--model musetalk`  
- 二次元：VRoid Studio / Ready Player Me（导出后另接，当前默认真人照片+Wav2Lip）

## 6. 合规

直播须持续标识「人工智能生成」，禁止虚假宣传。

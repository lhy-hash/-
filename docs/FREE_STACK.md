# 喜乐 · 站立/坐播数字人改造说明

按你列的工具栈，能本地落地的已接好；商业云能力用等价开源方案替代。

| 你要的 | 实际落地 |
|--------|----------|
| LivePortrait 表情 | idle 呼吸+轻转头微表情（完整 LivePortrait 需另装大模型） |
| MuseTalk / SadTalker 嘴型 | **Wav2Lip** 已跑通；MuseTalk 代码在仓，缺权重时可后装 |
| 即梦动作模仿 | 本地 **customvideo** 挥手/点头/指向（开播自动挥手） |
| Edge-TTS | 国内常不可达 → **通义 Qwen**，男 Ethan / 女 Cherry，强制匹配形象性别 |
| OBS | `start_xile_obs.ps1` 窗口捕获推流 |

## 四套形象（设置里一键选）

1. **女主播 · 站立** → 女声 Cherry  
2. **男主播 · 站立** → 男声 Ethan  
3. **女主播 · 坐播** → 女声  
4. **男主播 · 坐播** → 男声  

## 电脑

```powershell
# 女站立（默认，已加载肢体动作）
powershell -File C:\dev\LiveTalking\start_xile_engine.ps1

# 男站立
$env:XILE_HOST='male_stand'; powershell -File C:\dev\LiveTalking\start_xile_engine.ps1
```

## 手机

已装最新观众端。设置 → 选站立/坐播形象 → 进房 → 等「真实数字人」→ 开播会先挥手再开口。

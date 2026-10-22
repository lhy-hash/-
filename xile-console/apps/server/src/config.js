export const config = {
  port: Number(process.env.XILE_PORT || 8787),
  livetalking: (process.env.XILE_LIVETALKING || 'http://127.0.0.1:8010').replace(/\/$/, ''),
  ollama: (process.env.XILE_OLLAMA || 'http://127.0.0.1:11434').replace(/\/$/, ''),
  ollamaModel: process.env.XILE_OLLAMA_MODEL || 'qwen2.5:7b',
  defaultVoice: process.env.XILE_VOICE || 'zh-CN-XiaomengNeural',
};

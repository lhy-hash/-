import { config } from './config.js';

export async function ollamaHealthy() {
  try {
    const res = await fetch(`${config.ollama}/api/tags`, {
      signal: AbortSignal.timeout(2500),
    });
    return res.ok;
  } catch {
    return false;
  }
}

/**
 * 用 Ollama 生成口播稿；失败时返回 null（由调用方决定是否原文口播）
 */
export async function generateScript({
  userText,
  hostPersona = '',
  productContext = '',
}) {
  const system = [
    '你是直播间数字人主播，只输出可直接口播的中文口语短句。',
    '要求：自然、热情、像真人主播；不要用 markdown、列表、引号包裹全文。',
    '每段控制在 80～160 字；不要承诺无法兑现的功效或售后。',
    hostPersona ? `人设：${hostPersona}` : '',
    productContext ? `货品与话术背景：${productContext}` : '',
  ]
    .filter(Boolean)
    .join('\n');

  const res = await fetch(`${config.ollama}/api/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: config.ollamaModel,
      stream: false,
      messages: [
        { role: 'system', content: system },
        { role: 'user', content: userText },
      ],
      options: { temperature: 0.7, num_predict: 256 },
    }),
    signal: AbortSignal.timeout(120000),
  });

  if (!res.ok) {
    const body = await res.text().catch(() => '');
    throw new Error(`Ollama HTTP ${res.status}: ${body.slice(0, 200)}`);
  }

  const data = await res.json();
  const text = String(data?.message?.content || '')
    .replace(/\*\*/g, '')
    .replace(/^["「]|["」]$/g, '')
    .trim();
  if (!text) throw new Error('Ollama 返回空内容');
  return text;
}

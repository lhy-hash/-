import { config } from './config.js';
import { generateScript, ollamaHealthy } from './ollama.js';
import { listSessions, speak } from './livetalking.js';

const processing = new Set();

async function listPendingAsks(roomId = '') {
  const q = new URLSearchParams({ pending: '1' });
  if (roomId) q.set('id', roomId);
  const res = await fetch(`${config.livetalking}/api/xile/asks?${q}`, {
    signal: AbortSignal.timeout(8000),
  });
  if (!res.ok) throw new Error(`asks HTTP ${res.status}`);
  const body = await res.json();
  const asks = body?.data?.asks || [];
  return Array.isArray(asks) ? asks : [];
}

async function markAnswered({ id, answer, roomId }) {
  const res = await fetch(`${config.livetalking}/api/xile/ask/answer`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ id, answer, roomId }),
    signal: AbortSignal.timeout(8000),
  });
  if (!res.ok) {
    const t = await res.text();
    throw new Error(t || `answer HTTP ${res.status}`);
  }
  return res.json();
}

async function speakAllSessions(text, voice) {
  let sessions = [];
  try {
    sessions = await listSessions();
  } catch {
    sessions = [];
  }
  if (!sessions.length) {
    return speak({ text, interrupt: true, voice });
  }
  let last = null;
  for (const s of sessions) {
    const sid = String(s.sessionid || '');
    if (!sid) continue;
    last = await speak({
      text,
      sessionid: sid,
      interrupt: true,
      voice,
    });
  }
  return last;
}

/**
 * @param {{ broadcast: (e: object) => void, getContext: () => { hostPersona: string, productContext: string, voice: string, roomId: string, enabled: boolean } }} opts
 */
export function startAskPoller({ broadcast, getContext }) {
  const intervalMs = Number(process.env.XILE_ASK_POLL_MS || 2000);

  async function tick() {
    const ctx = getContext();
    if (!ctx.enabled) return;

    let asks = [];
    try {
      asks = await listPendingAsks(ctx.roomId || '');
    } catch (err) {
      broadcast({
        type: 'error',
        stage: 'ask_poll',
        message: err instanceof Error ? err.message : String(err),
      });
      return;
    }

    for (const ask of asks) {
      const id = String(ask.id || '');
      const text = String(ask.text || '').trim();
      const roomId = String(ask.roomId || ctx.roomId || '');
      if (!id || !text || processing.has(id)) continue;
      processing.add(id);

      broadcast({
        type: 'ask_received',
        id,
        text,
        roomId,
        source: ask.source || '',
      });

      try {
        let answer = text;
        let fallback = true;
        if (await ollamaHealthy()) {
          try {
            answer = await generateScript({
              userText: `观众提问：${text}\n请用主播口吻直接回答，简短口语。`,
              hostPersona: ctx.hostPersona,
              productContext: ctx.productContext,
            });
            fallback = false;
          } catch (err) {
            broadcast({
              type: 'error',
              stage: 'ask_llm',
              message: err instanceof Error ? err.message : String(err),
            });
            answer = `收到，关于「${text}」我这边稍后再细说，先看挂链详情哈。`;
            fallback = true;
          }
        } else {
          answer = `收到提问：${text}。家人们稍等，我按商品页说明给你们讲清楚。`;
        }

        broadcast({
          type: 'ask_answering',
          id,
          text,
          answer,
          fallback,
        });

        await speakAllSessions(answer, ctx.voice);
        await markAnswered({ id, answer, roomId });

        broadcast({
          type: 'ask_answered',
          id,
          text,
          answer,
          roomId,
          fallback,
        });
      } catch (err) {
        broadcast({
          type: 'error',
          stage: 'ask_handle',
          message: err instanceof Error ? err.message : String(err),
          askId: id,
        });
        // 失败也标记 done，避免死循环；可改成重试
        try {
          await markAnswered({
            id,
            answer: '刚才网络卡了一下，请再问一次。',
            roomId,
          });
        } catch {
          /* ignore */
        }
      } finally {
        processing.delete(id);
      }
    }
  }

  const timer = setInterval(() => {
    void tick();
  }, intervalMs);
  void tick();

  return () => clearInterval(timer);
}

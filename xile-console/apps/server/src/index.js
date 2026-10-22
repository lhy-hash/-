import Fastify from 'fastify';
import cors from '@fastify/cors';
import websocket from '@fastify/websocket';
import { config } from './config.js';
import { generateScript, ollamaHealthy } from './ollama.js';
import {
  interrupt as ltInterrupt,
  listSessions,
  livetalkingHealthy,
  speak,
} from './livetalking.js';
import { startAskPoller } from './ask-poller.js';

const app = Fastify({ logger: true });
const wsClients = new Set();

/** 控台可热更新的问答上下文（手机提问用） */
const askContext = {
  enabled: true,
  roomId: process.env.XILE_ROOM_ID || 'room_food',
  hostPersona:
    process.env.XILE_HOST_PERSONA ||
    '美食主播喜喜，女声，甜、活泼，像真人带货，不夸大。',
  productContext:
    process.env.XILE_PRODUCT ||
    '午市双人套餐，约128元，含主食小食饮品，到店核销，周末规则以商品页为准。',
  voice: config.defaultVoice,
};

function broadcast(event) {
  const raw = JSON.stringify(event);
  for (const socket of wsClients) {
    try {
      if (socket.readyState === 1) socket.send(raw);
    } catch {
      /* ignore */
    }
  }
}

await app.register(cors, { origin: true });
await app.register(websocket);

app.get('/api/health', async () => {
  const [livetalking, ollama] = await Promise.all([
    livetalkingHealthy(),
    ollamaHealthy(),
  ]);
  let sessions = [];
  if (livetalking) {
    try {
      sessions = await listSessions();
    } catch {
      sessions = [];
    }
  }
  return {
    ok: true,
    livetalking: { ok: livetalking, base: config.livetalking },
    ollama: { ok: ollama, base: config.ollama, model: config.ollamaModel },
    sessions,
  };
});

app.get('/api/sessions', async () => {
  const sessions = await listSessions();
  return { ok: true, sessions };
});

app.post('/api/chat', async (request, reply) => {
  const body = request.body || {};
  const userText = String(body.text || body.prompt || '').trim();
  if (!userText) {
    return reply.code(400).send({ ok: false, error: 'text 不能为空' });
  }

  broadcast({ type: 'generating', text: userText });

  const ollamaOk = await ollamaHealthy();
  if (!ollamaOk) {
    broadcast({
      type: 'chat_fallback',
      text: userText,
      reason: 'Ollama 不可用，将使用原文',
    });
    return {
      ok: true,
      fallback: true,
      script: userText,
      message: 'Ollama 未启动，已返回原文，可直接口播',
    };
  }

  try {
    const script = await generateScript({
      userText,
      hostPersona: String(body.hostPersona || ''),
      productContext: String(body.productContext || ''),
    });
    broadcast({ type: 'generated', script });
    return { ok: true, fallback: false, script };
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    broadcast({ type: 'error', stage: 'chat', message });
    // Ollama 失败也允许原文口播
    return {
      ok: true,
      fallback: true,
      script: userText,
      message: `LLM 失败，已回退原文：${message}`,
    };
  }
});

app.post('/api/speak', async (request, reply) => {
  const body = request.body || {};
  const text = String(body.text || '').trim();
  if (!text) {
    return reply.code(400).send({ ok: false, error: 'text 不能为空' });
  }

  broadcast({ type: 'speaking', text });
  try {
    const result = await speak({
      text,
      sessionid: body.sessionid,
      interrupt: body.interrupt !== false,
      voice: body.voice || config.defaultVoice,
    });
    broadcast({ type: 'spoken', text, sessionid: result.sessionid });
    return { ok: true, ...result };
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    broadcast({ type: 'error', stage: 'speak', message });
    return reply.code(502).send({ ok: false, error: message });
  }
});

app.post('/api/chat_and_speak', async (request, reply) => {
  const body = request.body || {};
  const userText = String(body.text || '').trim();
  if (!userText) {
    return reply.code(400).send({ ok: false, error: 'text 不能为空' });
  }

  broadcast({ type: 'generating', text: userText });
  let script = userText;
  let fallback = true;
  let chatMessage = '';

  const ollamaOk = await ollamaHealthy();
  if (ollamaOk) {
    try {
      script = await generateScript({
        userText,
        hostPersona: String(body.hostPersona || ''),
        productContext: String(body.productContext || ''),
      });
      fallback = false;
      broadcast({ type: 'generated', script });
    } catch (err) {
      chatMessage = err instanceof Error ? err.message : String(err);
      broadcast({ type: 'error', stage: 'chat', message: chatMessage });
      script = userText;
      fallback = true;
    }
  } else {
    chatMessage = 'Ollama 未启动，使用原文口播';
    broadcast({ type: 'chat_fallback', text: userText, reason: chatMessage });
  }

  broadcast({ type: 'speaking', text: script });
  try {
    const result = await speak({
      text: script,
      sessionid: body.sessionid,
      interrupt: body.interrupt !== false,
      voice: body.voice || config.defaultVoice,
    });
    broadcast({ type: 'spoken', text: script, sessionid: result.sessionid });
    return {
      ok: true,
      script,
      fallback,
      message: chatMessage || undefined,
      ...result,
    };
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    broadcast({ type: 'error', stage: 'speak', message });
    return reply.code(502).send({
      ok: false,
      script,
      fallback,
      error: message,
    });
  }
});

app.post('/api/interrupt', async (request, reply) => {
  const body = request.body || {};
  try {
    const result = await ltInterrupt(body.sessionid);
    broadcast({ type: 'interrupted', sessionid: result.sessionid });
    return { ok: true, ...result };
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    broadcast({ type: 'error', stage: 'interrupt', message });
    return reply.code(502).send({ ok: false, error: message });
  }
});

app.get('/api/ask-settings', async () => ({ ok: true, ...askContext }));

app.post('/api/ask-settings', async (request) => {
  const body = request.body || {};
  if (typeof body.enabled === 'boolean') askContext.enabled = body.enabled;
  if (body.roomId != null) askContext.roomId = String(body.roomId);
  if (body.hostPersona != null) askContext.hostPersona = String(body.hostPersona);
  if (body.productContext != null) {
    askContext.productContext = String(body.productContext);
  }
  if (body.voice != null) askContext.voice = String(body.voice);
  broadcast({ type: 'ask_settings', ...askContext });
  return { ok: true, ...askContext };
});

app.get('/ws', { websocket: true }, (socket) => {
  wsClients.add(socket);
  socket.send(
    JSON.stringify({
      type: 'hello',
      livetalking: config.livetalking,
      ollamaModel: config.ollamaModel,
      askSync: askContext.enabled,
      roomId: askContext.roomId,
    }),
  );
  socket.on('close', () => wsClients.delete(socket));
  socket.on('error', () => wsClients.delete(socket));
});

startAskPoller({
  broadcast,
  getContext: () => ({ ...askContext }),
});

try {
  await app.listen({ port: config.port, host: '0.0.0.0' });
  console.log(`[xile-server] http://127.0.0.1:${config.port}`);
  console.log(`[xile-server] LiveTalking → ${config.livetalking}`);
  console.log(`[xile-server] Ollama → ${config.ollama} (${config.ollamaModel})`);
  console.log(
    `[xile-server] 手机提问同步 → room=${askContext.roomId} enabled=${askContext.enabled}`,
  );
} catch (err) {
  app.log.error(err);
  process.exit(1);
}

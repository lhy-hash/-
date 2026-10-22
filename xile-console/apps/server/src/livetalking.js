import { config } from './config.js';

export async function livetalkingHealthy() {
  try {
    const res = await fetch(`${config.livetalking}/`, {
      signal: AbortSignal.timeout(2500),
    });
    return res.status >= 200 && res.status < 500;
  } catch {
    return false;
  }
}

export async function listSessions() {
  const res = await fetch(`${config.livetalking}/api/admin/sessions`, {
    signal: AbortSignal.timeout(5000),
  });
  if (!res.ok) throw new Error(`sessions HTTP ${res.status}`);
  const body = await res.json();
  const sessions = body?.data?.sessions || body?.sessions || [];
  return Array.isArray(sessions) ? sessions : [];
}

/** 优先用客户端传入的 sessionid，否则取最新活跃会话 */
export async function resolveSessionId(preferred) {
  const want = String(preferred || '').trim();
  if (want) return want;
  const sessions = await listSessions();
  if (!sessions.length) return '';
  return String(sessions[sessions.length - 1].sessionid || '');
}

export async function speak({
  text,
  sessionid = '',
  interrupt = true,
  voice = config.defaultVoice,
}) {
  const sid = await resolveSessionId(sessionid);
  const payload = {
    sessionid: sid,
    text: String(text || '').trim(),
    type: 'echo',
    interrupt: Boolean(interrupt),
  };
  if (voice) {
    payload.tts = { ref_file: voice, voice };
  }

  const res = await fetch(`${config.livetalking}/human`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(30000),
  });
  const bodyText = await res.text();
  let body;
  try {
    body = JSON.parse(bodyText);
  } catch {
    body = { raw: bodyText };
  }
  if (!res.ok) {
    throw new Error(body?.msg || body?.message || `human HTTP ${res.status}`);
  }
  return { sessionid: sid, result: body };
}

export async function interrupt(sessionid = '') {
  const sid = await resolveSessionId(sessionid);
  const res = await fetch(`${config.livetalking}/interrupt_talk`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ sessionid: sid }),
    signal: AbortSignal.timeout(10000),
  });
  if (!res.ok) {
    const t = await res.text();
    throw new Error(t || `interrupt HTTP ${res.status}`);
  }
  return { sessionid: sid };
}

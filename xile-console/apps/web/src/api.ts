const API = '';

export type Health = {
  ok: boolean;
  livetalking: { ok: boolean; base: string };
  ollama: { ok: boolean; base: string; model: string };
  sessions: Array<{ sessionid: string; speaking?: boolean; avatar_id?: string }>;
};

async function json<T>(url: string, init?: RequestInit): Promise<T> {
  const res = await fetch(`${API}${url}`, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      ...(init?.headers || {}),
    },
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error((data as { error?: string }).error || `HTTP ${res.status}`);
  }
  return data as T;
}

export function fetchHealth() {
  return json<Health>('/api/health');
}

export function chat(body: {
  text: string;
  hostPersona?: string;
  productContext?: string;
}) {
  return json<{
    ok: boolean;
    script: string;
    fallback?: boolean;
    message?: string;
  }>('/api/chat', { method: 'POST', body: JSON.stringify(body) });
}

export function speak(body: {
  text: string;
  sessionid?: string;
  interrupt?: boolean;
  voice?: string;
}) {
  return json<{ ok: boolean; sessionid?: string }>('/api/speak', {
    method: 'POST',
    body: JSON.stringify(body),
  });
}

export function chatAndSpeak(body: {
  text: string;
  sessionid?: string;
  hostPersona?: string;
  productContext?: string;
  voice?: string;
  interrupt?: boolean;
}) {
  return json<{
    ok: boolean;
    script: string;
    fallback?: boolean;
    message?: string;
    sessionid?: string;
  }>('/api/chat_and_speak', { method: 'POST', body: JSON.stringify(body) });
}

export function interrupt(sessionid?: string) {
  return json<{ ok: boolean }>('/api/interrupt', {
    method: 'POST',
    body: JSON.stringify({ sessionid: sessionid || '' }),
  });
}

export function fetchAskSettings() {
  return json<{
    ok: boolean;
    enabled: boolean;
    roomId: string;
    hostPersona: string;
    productContext: string;
    voice: string;
  }>('/api/ask-settings');
}

export function saveAskSettings(body: {
  enabled?: boolean;
  roomId?: string;
  hostPersona?: string;
  productContext?: string;
  voice?: string;
}) {
  return json('/api/ask-settings', {
    method: 'POST',
    body: JSON.stringify(body),
  });
}

export function connectStatusWs(onEvent: (ev: Record<string, unknown>) => void) {
  const proto = location.protocol === 'https:' ? 'wss' : 'ws';
  const ws = new WebSocket(`${proto}://${location.host}/ws`);
  ws.onmessage = (e) => {
    try {
      onEvent(JSON.parse(String(e.data)));
    } catch {
      /* ignore */
    }
  };
  return ws;
}

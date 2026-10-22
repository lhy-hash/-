<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue';
import {
  chat,
  chatAndSpeak,
  connectStatusWs,
  fetchHealth,
  interrupt,
  saveAskSettings,
  speak,
  type Health,
} from './api';

const ENGINE = 'http://127.0.0.1:8010';
const previewUrl = `${ENGINE}/xile_preview.html`;

const health = ref<Health | null>(null);
const wsOk = ref(false);
const busy = ref(false);
const error = ref('');
const logs = ref<string[]>([]);
const askFeed = ref<Array<{ id: string; q: string; a?: string; status: string }>>([]);
const askSyncOn = ref(true);
const roomId = ref('room_food');

const prompt = ref('家人们好，今天这款午市双人套餐大概128，到店核销，两个人吃刚刚好。帮我再讲一段用法。');
const script = ref('');
const hostPersona = ref('美食主播喜喜，女声，甜、活泼，像真人带货，不夸大。');
const productContext = ref('午市双人套餐，约128元，含主食小食饮品，到店核销，周末规则以商品页为准。');
const voice = ref('zh-CN-XiaomengNeural');
const sessionid = ref('');

const ltOk = computed(() => !!health.value?.livetalking.ok);
const ollamaOk = computed(() => !!health.value?.ollama.ok);
const latestSession = computed(() => {
  const list = health.value?.sessions || [];
  return list.length ? list[list.length - 1].sessionid : '';
});

function log(line: string) {
  const t = new Date().toLocaleTimeString();
  logs.value = [`${t}  ${line}`, ...logs.value].slice(0, 40);
}

async function refresh() {
  try {
    health.value = await fetchHealth();
    if (!sessionid.value && latestSession.value) {
      sessionid.value = latestSession.value;
    }
  } catch (e) {
    health.value = null;
    error.value = e instanceof Error ? e.message : String(e);
  }
}

function activeSession() {
  return sessionid.value.trim() || latestSession.value;
}

async function onGenerate() {
  const text = prompt.value.trim();
  if (!text) return;
  busy.value = true;
  error.value = '';
  try {
    const res = await chat({
      text,
      hostPersona: hostPersona.value,
      productContext: productContext.value,
    });
    script.value = res.script;
    log(res.fallback ? `LLM 回退原文：${res.message || ''}` : '已生成口播稿');
  } catch (e) {
    error.value = e instanceof Error ? e.message : String(e);
  } finally {
    busy.value = false;
  }
}

async function onSpeak() {
  const text = (script.value || prompt.value).trim();
  if (!text) return;
  busy.value = true;
  error.value = '';
  try {
    const res = await speak({
      text,
      sessionid: activeSession(),
      voice: voice.value,
      interrupt: true,
    });
    if (res.sessionid) sessionid.value = res.sessionid;
    log(`已口播 · session ${res.sessionid || '-'}`);
  } catch (e) {
    error.value = e instanceof Error ? e.message : String(e);
    log(`口播失败：${error.value}`);
  } finally {
    busy.value = false;
    void refresh();
  }
}

async function onGenerateAndSpeak() {
  const text = prompt.value.trim();
  if (!text) return;
  busy.value = true;
  error.value = '';
  try {
    const res = await chatAndSpeak({
      text,
      sessionid: activeSession(),
      hostPersona: hostPersona.value,
      productContext: productContext.value,
      voice: voice.value,
      interrupt: true,
    });
    script.value = res.script;
    if (res.sessionid) sessionid.value = res.sessionid;
    log(
      res.fallback
        ? `原文口播（${res.message || 'LLM 不可用'}）`
        : `生成并口播 · ${res.sessionid || ''}`,
    );
  } catch (e) {
    error.value = e instanceof Error ? e.message : String(e);
    log(`失败：${error.value}`);
  } finally {
    busy.value = false;
    void refresh();
  }
}

async function onInterrupt() {
  error.value = '';
  try {
    await interrupt(activeSession());
    log('已打断');
  } catch (e) {
    error.value = e instanceof Error ? e.message : String(e);
  }
}

async function pushAskSettings() {
  try {
    await saveAskSettings({
      enabled: askSyncOn.value,
      roomId: roomId.value,
      hostPersona: hostPersona.value,
      productContext: productContext.value,
      voice: voice.value,
    });
    log(`提问同步已${askSyncOn.value ? '开启' : '关闭'} · ${roomId.value}`);
  } catch (e) {
    log(`同步设置失败：${e instanceof Error ? e.message : e}`);
  }
}

function upsertAsk(id: string, patch: Partial<{ q: string; a: string; status: string }>) {
  const i = askFeed.value.findIndex((x) => x.id === id);
  if (i < 0) {
    askFeed.value = [
      { id, q: patch.q || '', a: patch.a, status: patch.status || '' },
      ...askFeed.value,
    ].slice(0, 30);
  } else {
    askFeed.value[i] = { ...askFeed.value[i], ...patch };
  }
}

let timer = 0;
let ws: WebSocket | null = null;

onMounted(() => {
  void refresh();
  void pushAskSettings();
  timer = window.setInterval(() => void refresh(), 4000);
  ws = connectStatusWs((ev) => {
    wsOk.value = true;
    const type = String(ev.type || '');
    if (type === 'hello') {
      log('状态通道已连接（含手机提问同步）');
      if (ev.roomId) roomId.value = String(ev.roomId);
      if (typeof ev.askSync === 'boolean') askSyncOn.value = ev.askSync;
    } else if (type === 'generating') log('正在生成口播…');
    else if (type === 'generated') log('口播稿已生成');
    else if (type === 'speaking') log('正在驱动数字人…');
    else if (type === 'spoken') log(`口播完成 ${ev.sessionid || ''}`);
    else if (type === 'interrupted') log('已打断当前句');
    else if (type === 'error') log(`错误：${ev.message || ''}`);
    else if (type === 'chat_fallback') log('Ollama 不可用，使用原文');
    else if (type === 'ask_received') {
      upsertAsk(String(ev.id), { q: String(ev.text || ''), status: '收到提问' });
      log(`手机提问：${ev.text || ''}`);
    } else if (type === 'ask_answering') {
      upsertAsk(String(ev.id), {
        q: String(ev.text || ''),
        a: String(ev.answer || ''),
        status: '回答中',
      });
      script.value = String(ev.answer || script.value);
      log('正在回答手机提问…');
    } else if (type === 'ask_answered') {
      upsertAsk(String(ev.id), {
        q: String(ev.text || ''),
        a: String(ev.answer || ''),
        status: '已同步公屏',
      });
      log('手机提问已回答并写回公屏');
    }
  });
  ws.onopen = () => {
    wsOk.value = true;
  };
  ws.onclose = () => {
    wsOk.value = false;
  };
});

onUnmounted(() => {
  window.clearInterval(timer);
  ws?.close();
});
</script>

<template>
  <div class="page">
    <header class="banner">
      OBS 推流：场景里添加「窗口采集」或「浏览器源」，对准本页右侧预览（或
      <a :href="previewUrl" target="_blank">单独打开预览页</a>
      ）。音频选系统声 / 浏览器。推流地址和密钥在 OBS 里手工填写。
    </header>

    <div class="status">
      <span :class="['dot', ltOk ? 'ok' : 'bad']">LiveTalking {{ ltOk ? '在线' : '离线' }}</span>
      <span :class="['dot', ollamaOk ? 'ok' : 'warn']">Ollama {{ ollamaOk ? '在线' : '离线（可原文口播）' }}</span>
      <span :class="['dot', wsOk ? 'ok' : 'bad']">WebSocket {{ wsOk ? '已连' : '未连' }}</span>
      <span class="muted">会话 {{ activeSession() || '等待预览接通' }}</span>
    </div>

    <main class="layout">
      <section class="panel controls">
        <h1>喜乐控台</h1>
        <p class="hint">输入 → 本地 Ollama 生成口播 → LiveTalking 实时出镜。手机提问由本机自动回答并写回公屏。</p>

        <div class="row">
          <div class="field grow">
            <label>同步房间 ID</label>
            <input v-model="roomId" @change="pushAskSettings" />
          </div>
          <div class="field" style="display:flex;align-items:flex-end;padding-bottom:12px">
            <label style="display:flex;gap:8px;align-items:center;margin:0;color:var(--text)">
              <input v-model="askSyncOn" type="checkbox" @change="pushAskSettings" />
              手机提问自动答
            </label>
          </div>
        </div>

        <div class="field">
          <label>主播人设</label>
          <textarea v-model="hostPersona" rows="2" @change="pushAskSettings" />
        </div>
        <div class="field">
          <label>货品 / 话术背景</label>
          <textarea v-model="productContext" rows="2" @change="pushAskSettings" />
        </div>
        <div class="row">
          <div class="field grow">
            <label>EdgeTTS 音色</label>
            <input v-model="voice" />
          </div>
          <div class="field grow">
            <label>sessionid（空则用最新会话）</label>
            <input v-model="sessionid" placeholder="预览接通后自动填" />
          </div>
        </div>
        <div class="field">
          <label>控台输入</label>
          <textarea v-model="prompt" rows="4" />
        </div>
        <div class="field">
          <label>口播稿（生成后可改）</label>
          <textarea v-model="script" rows="5" placeholder="点「只生成」或「生成并口播」后出现" />
        </div>

        <div class="actions">
          <button :disabled="busy" @click="onGenerate">只生成</button>
          <button :disabled="busy" @click="onGenerateAndSpeak">生成并口播</button>
          <button class="secondary" :disabled="busy" @click="onSpeak">直接口播</button>
          <button class="danger" @click="onInterrupt">打断</button>
        </div>
        <p v-if="error" class="err">{{ error }}</p>
        <p class="hint">手机进「美食直播间」提问后，这里会显示问答；数字人在电脑预览口播，公屏同步回手机。</p>

        <div v-if="askFeed.length" class="ask-feed">
          <div v-for="item in askFeed" :key="item.id" class="ask-item">
            <div class="ask-q">问：{{ item.q }}</div>
            <div v-if="item.a" class="ask-a">答：{{ item.a }}</div>
            <div class="ask-st">{{ item.status }}</div>
          </div>
        </div>

        <ul class="logs">
          <li v-for="(line, i) in logs" :key="i">{{ line }}</li>
        </ul>
      </section>

      <section class="panel preview">
        <div class="preview-bar">
          <span>实时预览</span>
          <a :href="`${ENGINE}/index.html`" target="_blank">打开完整引擎页</a>
        </div>
        <iframe :src="previewUrl" title="LiveTalking 预览" allow="autoplay; microphone; camera" />
      </section>
    </main>
  </div>
</template>

<style scoped>
.page {
  min-height: 100vh;
  display: flex;
  flex-direction: column;
}
.banner {
  background: #1c2433;
  border-bottom: 1px solid var(--border);
  padding: 10px 16px;
  font-size: 13px;
  color: var(--warn);
}
.banner a,
.preview-bar a {
  color: #9ec1ff;
}
.status {
  display: flex;
  gap: 10px;
  flex-wrap: wrap;
  padding: 10px 16px;
  align-items: center;
}
.dot {
  font-size: 12px;
  padding: 4px 8px;
  border-radius: 999px;
  background: #222;
}
.dot.ok { color: var(--ok); }
.dot.bad { color: var(--bad); }
.dot.warn { color: var(--warn); }
.muted { color: var(--muted); font-size: 12px; }
.layout {
  display: grid;
  grid-template-columns: minmax(320px, 460px) 1fr;
  gap: 12px;
  padding: 0 12px 12px;
  flex: 1;
  min-height: 0;
}
.panel {
  background: var(--panel);
  border: 1px solid var(--border);
  border-radius: 14px;
  padding: 14px;
}
h1 { margin: 0 0 6px; font-size: 20px; }
.hint { color: var(--muted); font-size: 12px; line-height: 1.5; }
.row { display: flex; gap: 10px; }
.grow { flex: 1; }
.actions { display: flex; flex-wrap: wrap; gap: 8px; margin: 8px 0; }
.err { color: var(--bad); font-size: 13px; }
.logs {
  list-style: none;
  margin: 8px 0 0;
  padding: 0;
  max-height: 120px;
  overflow: auto;
  font-size: 12px;
  color: var(--muted);
}
.ask-feed {
  margin-top: 10px;
  max-height: 200px;
  overflow: auto;
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.ask-item {
  border: 1px solid var(--border);
  border-radius: 10px;
  padding: 8px 10px;
  background: #0c1017;
  font-size: 12px;
}
.ask-q { color: var(--text); margin-bottom: 4px; }
.ask-a { color: #9ec1ff; margin-bottom: 4px; }
.ask-st { color: var(--muted); font-size: 11px; }
.preview {
  display: flex;
  flex-direction: column;
  min-height: 70vh;
  padding: 0;
  overflow: hidden;
}
.preview-bar {
  display: flex;
  justify-content: space-between;
  padding: 10px 12px;
  font-size: 13px;
  border-bottom: 1px solid var(--border);
}
iframe {
  flex: 1;
  width: 100%;
  border: 0;
  background: #000;
  min-height: 520px;
}
@media (max-width: 960px) {
  .layout { grid-template-columns: 1fr; }
}
</style>

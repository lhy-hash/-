"""
IT技术面试辅助智能体 - 后端服务
核心特性：
1. 流式LLM响应，1秒内开始输出
2. 实时语音识别（阿里云Paraformer），捕获腾讯会议等系统音频
3. 识别到完整句子后自动生成回答
4. 支持简历上下文，回答贴合候选人背景
"""
import json
import time
import queue
import threading
import requests
from flask import Flask, request, Response, jsonify, render_template
from config import Config

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 20 * 1024 * 1024  # 最大20MB


@app.route("/")
def index():
    return render_template("index.html")


@app.route("/api/config")
def api_config():
    return jsonify({
        "configured": Config.is_configured(),
        "model": Config.LLM_MODEL,
        "base_url": Config.LLM_BASE_URL,
        "has_resume": bool(Config.RESUME_CONTEXT),
    })


@app.route("/api/resume", methods=["POST"])
def api_resume():
    """上传简历文本，存入上下文"""
    data = request.get_json(force=True, silent=True) or {}
    resume_text = (data.get("resume") or "").strip()
    Config.set_resume(resume_text)
    return jsonify({"ok": True, "length": len(resume_text), "msg": "简历已保存" if resume_text else "简历已清空"})


@app.route("/api/resume", methods=["GET"])
def api_resume_get():
    """获取当前保存的完整简历文本"""
    return jsonify({"ok": True, "resume": Config.RESUME_CONTEXT, "length": len(Config.RESUME_CONTEXT)})


@app.route("/api/resume/upload", methods=["POST"])
def api_resume_upload():
    """上传PDF/Word简历文件，自动解析文本"""
    if "file" not in request.files:
        return jsonify({"ok": False, "msg": "未收到文件"}), 400

    file = request.files["file"]
    filename = file.filename or ""
    if not filename:
        return jsonify({"ok": False, "msg": "文件名为空"}), 400

    ext = filename.rsplit(".", 1)[-1].lower()
    if ext not in ("pdf", "txt", "doc", "docx"):
        return jsonify({"ok": False, "msg": "仅支持 PDF / TXT / Word 格式"}), 400

    try:
        text = ""
        if ext == "pdf":
            import pdfplumber, io, logging
            # 抑制pdfplumber的FontBBox警告
            logging.getLogger("pdfplumber").setLevel(logging.ERROR)
            logging.getLogger("pdfminer").setLevel(logging.ERROR)
            logging.getLogger("pdfminer.pdffont").setLevel(logging.CRITICAL)
            data = file.read()
            with pdfplumber.open(io.BytesIO(data)) as pdf:
                for page in pdf.pages:
                    page_text = page.extract_text() or ""
                    text += page_text + "\n"
        elif ext == "txt":
            text = file.read().decode("utf-8", errors="ignore")
        elif ext in ("doc", "docx"):
            try:
                from docx import Document
                import io
                doc = Document(io.BytesIO(file.read()))
                text = "\n".join(p.text for p in doc.paragraphs)
            except ImportError:
                return jsonify({"ok": False, "msg": "解析Word需要python-docx，请用PDF或TXT"}), 400

        text = text.strip()
        if not text:
            return jsonify({"ok": False, "msg": "未能从文件中提取文本，请检查文件是否为扫描版PDF"}), 400

        Config.set_resume(text)
        print(f"[简历] 解析成功，共 {len(text)} 字", flush=True)
        return jsonify({
            "ok": True,
            "msg": "简历解析成功",
            "length": len(text),
            "resume": text,
        })
    except Exception as e:
        import traceback
        print(f"[简历] 解析失败: {traceback.format_exc()}", flush=True)
        return jsonify({"ok": False, "msg": "解析失败: %s" % str(e)}), 500


# ==================== LLM 流式调用 ====================

def stream_llm_response(question, context=""):
    """流式调用LLM，逐字返回回答内容"""
    print(f"[LLM] 收到问题: {question[:50]}", flush=True)
    headers = {
        "Authorization": f"Bearer {Config.LLM_API_KEY}",
        "Content-Type": "application/json",
    }

    messages = [
        {"role": "system", "content": Config.get_system_prompt()},
    ]

    if context:
        try:
            history = json.loads(context)
            for msg in history:
                messages.append(msg)
        except Exception:
            pass

    messages.append({"role": "user", "content": question})

    payload = {
        "model": Config.LLM_MODEL,
        "messages": messages,
        "max_tokens": Config.LLM_MAX_TOKENS,
        "temperature": Config.LLM_TEMPERATURE,
        "stream": True,
    }

    url = f"{Config.LLM_BASE_URL.rstrip('/')}/chat/completions"

    try:
        resp = requests.post(
            url,
            headers=headers,
            json=payload,
            stream=True,
            timeout=(3, 60),
        )
        resp.raise_for_status()

        for line in resp.iter_lines(decode_unicode=True):
            if not line:
                continue
            if line.startswith("data: "):
                data_str = line[6:]
                if data_str.strip() == "[DONE]":
                    break
                try:
                    data = json.loads(data_str)
                    delta = data.get("choices", [{}])[0].get("delta", {})
                    content = delta.get("content", "")
                    if content:
                        yield content
                except json.JSONDecodeError:
                    continue

    except requests.exceptions.Timeout:
        yield "[ERROR] 请求超时，请检查网络或API配置"
    except requests.exceptions.ConnectionError:
        yield "[ERROR] 无法连接到LLM服务，请检查BASE_URL和API Key"
    except Exception as e:
        yield f"[ERROR] 请求出错: {str(e)}"


@app.route("/api/ask", methods=["POST"])
def api_ask():
    """手动输入问题，流式返回回答"""
    if not Config.is_configured():
        return jsonify({"error": "请先在 .env 文件中配置 LLM_API_KEY"}), 400

    data = request.get_json(force=True, silent=True) or {}
    question = (data.get("question") or "").strip()
    context = data.get("context", "")

    if not question:
        return jsonify({"error": "问题不能为空"}), 400

    start_time = time.time()

    def generate():
        yield f"data: {json.dumps({'start': True}, ensure_ascii=False)}\n\n"
        for chunk in stream_llm_response(question, context):
            if chunk.startswith("[ERROR]"):
                yield f"data: {json.dumps({'error': chunk}, ensure_ascii=False)}\n\n"
            else:
                yield f"data: {json.dumps({'content': chunk}, ensure_ascii=False)}\n\n"
        yield f"data: {json.dumps({'done': True, 'elapsed': round(time.time() - start_time, 2)}, ensure_ascii=False)}\n\n"

    return Response(
        generate(),
        mimetype="text/event-stream",
        headers={
            "Cache-Control": "no-cache, no-transform",
            "X-Accel-Buffering": "no",
            "Connection": "keep-alive",
            "Access-Control-Allow-Origin": "*",
        },
    )


# ==================== 语音识别 (ASR) ====================

import audio_capture

# 存储最近的对话上下文（用于多轮）
_recent_qa = []


@app.route("/api/asr/devices")
def api_asr_devices():
    """列出音频输入设备"""
    try:
        devices = audio_capture.list_audio_devices()
        return jsonify({"ok": True, "devices": devices})
    except Exception as e:
        return jsonify({"ok": False, "msg": str(e), "devices": []})


@app.route("/api/asr/start", methods=["POST"])
def api_asr_start():
    """启动语音识别"""
    global _processor_running
    _processor_running = False  # 重置处理器状态，允许重新启动
    data = request.get_json(force=True, silent=True) or {}
    device_index = data.get("device_index")
    result = audio_capture.start_capture(device_index=device_index)
    if result.get("ok"):
        start_processor()  # 启动后台处理线程
    return jsonify(result)


@app.route("/api/asr/stop", methods=["POST"])
def api_asr_stop():
    """停止语音识别"""
    result = audio_capture.stop_capture()
    return jsonify(result)


@app.route("/api/asr/status")
def api_asr_status():
    return jsonify({"running": audio_capture.is_running()})


# 全局事件队列：后台线程处理识别+LLM，结果存入队列，前端轮询取数据
_event_queue = queue.Queue(maxsize=2000)
_processor_thread = None
_processor_running = False


def start_processor():
    """启动后台处理线程：识别结果 → 静音检测 → LLM回答 → 事件队列"""
    global _processor_thread, _processor_running
    if _processor_running:
        return
    _processor_running = True

    QUESTION_KEYWORDS = [
        "什么", "怎么", "为什么", "哪", "吗", "呢", "吧",
        "介绍", "说说", "讲讲", "聊聊", "谈谈", "请问",
        "区别", "原理", "实现", "如何", "是否", "有没有",
        "了解", "熟悉", "用过", "做过", "项目", "经验",
        "？", "?", "几", "多少",
    ]

    def is_question(text):
        t = text.strip()
        if len(t) < 4:
            return False
        if "？" in t or "?" in t:
            return True
        for kw in QUESTION_KEYWORDS:
            if kw in t:
                return True
        return False

    def push_event(evt):
        try:
            _event_queue.put_nowait(evt)
        except queue.Full:
            pass  # 队列满了就丢弃旧数据

    def process_loop():
        global _recent_qa
        current_partial = ""
        last_voice_time = time.time()
        SILENCE_THRESHOLD = 5.0
        SILENCE_DURATION = 1.2

        while _processor_running and audio_capture.is_running():
            results = audio_capture.get_results()
            now = time.time()
            for item in results:
                if "volume" in item:
                    vol = item["volume"]
                    push_event({"type": "volume", "value": vol})
                    if vol > SILENCE_THRESHOLD:
                        last_voice_time = now
                    elif current_partial and (now - last_voice_time) > SILENCE_DURATION:
                        # 静音超时 → flush
                        text = current_partial.strip()
                        current_partial = ""
                        if len(text) >= 2:
                            is_q = is_question(text)
                            print(f"[ASR] 句子: {text[:40]} | 是问题: {is_q}", flush=True)
                            push_event({"type": "question", "text": text})
                            if is_q and Config.is_configured():
                                push_event({"type": "thinking", "text": "正在生成回答..."})
                                context = json.dumps(_recent_qa[-6:])
                                full_answer = ""
                                for chunk in stream_llm_response(text, context):
                                    if chunk.startswith("[ERROR]"):
                                        push_event({"type": "answer_error", "msg": chunk})
                                        break
                                    full_answer += chunk
                                    push_event({"type": "answer", "content": chunk})
                                push_event({"type": "answer_done"})
                                if full_answer and not full_answer.startswith("[ERROR]"):
                                    _recent_qa.append({"role": "user", "content": text})
                                    _recent_qa.append({"role": "assistant", "content": full_answer})
                                    if len(_recent_qa) > 20:
                                        _recent_qa = _recent_qa[-20:]
                    continue

                text = item["text"]
                if not item["final"]:
                    current_partial = text
                    push_event({"type": "partial", "text": text})
                else:
                    current_partial = ""
                    text = text.strip()
                    if len(text) >= 2:
                        is_q = is_question(text)
                        print(f"[ASR] 句子: {text[:40]} | 是问题: {is_q}", flush=True)
                        push_event({"type": "question", "text": text})
                        if is_q and Config.is_configured():
                            push_event({"type": "thinking", "text": "正在生成回答..."})
                            context = json.dumps(_recent_qa[-6:])
                            full_answer = ""
                            for chunk in stream_llm_response(text, context):
                                if chunk.startswith("[ERROR]"):
                                    push_event({"type": "answer_error", "msg": chunk})
                                    break
                                full_answer += chunk
                                push_event({"type": "answer", "content": chunk})
                            push_event({"type": "answer_done"})
                            if full_answer and not full_answer.startswith("[ERROR]"):
                                _recent_qa.append({"role": "user", "content": text})
                                _recent_qa.append({"role": "assistant", "content": full_answer})
                                if len(_recent_qa) > 20:
                                    _recent_qa = _recent_qa[-20:]
            time.sleep(0.05)

    _processor_thread = threading.Thread(target=process_loop, daemon=True)
    _processor_thread.start()
    print("[处理器] 后台处理线程已启动", flush=True)


@app.route("/api/asr/stream")
def api_asr_stream():
    """轮询接口：返回队列中的所有事件（公网稳定方案）"""
    if not audio_capture.is_running():
        start_processor()
    events = []
    try:
        while True:
            events.append(_event_queue.get_nowait())
    except queue.Empty:
        pass
    return jsonify({"events": events})


@app.route("/api/health")
def api_health():
    return jsonify({"status": "ok", "configured": Config.is_configured()})


if __name__ == "__main__":
    print("=" * 60)
    print("  IT技术面试辅助智能体 启动中...")
    print(f"  模型: {Config.LLM_MODEL}")
    print(f"  已配置API Key: {'是' if Config.is_configured() else '否'}")
    print(f"  已加载简历: {'是' if Config.RESUME_CONTEXT else '否'}")
    if not Config.is_configured():
        print("  ⚠ 警告: 请复制 .env.example 为 .env 并填写 LLM_API_KEY")
    print("  访问地址: http://127.0.0.1:5000")
    print("=" * 60)
    app.run(host="0.0.0.0", port=5000, debug=False, threaded=True)

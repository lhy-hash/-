"""
音频捕获 + 阿里云 Paraformer 实时语音识别模块
使用 pyaudiowpatch 支持 WASAPI loopback，捕获系统音频（腾讯会议等）
"""
import os
import time
import queue
import threading
import numpy as np

import pyaudiowpatch as pyaudio
import dashscope
from dashscope.audio.asr import Recognition, RecognitionCallback, RecognitionResult
from dotenv import load_dotenv

load_dotenv(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env"))

# 全局状态
_p = None
_stream = None
_is_running = False
_result_queue = queue.Queue()
_volume_queue = queue.Queue()
_device_index = None
_orig_samplerate = 16000
_channels = 2
_read_thread = None
_recognition = None
_recorded_pcm = []  # 保存会话音频用于诊断
SAVE_AUDIO = os.getenv("SAVE_AUDIO", "1") == "1"

# 阿里云API Key从环境变量读取
dashscope.api_key = os.getenv("LLM_API_KEY", "")
ASR_MODEL = os.getenv("ASR_MODEL", "qwen-audio-3.1-asr-flash-streaming")


class _AsrCallback(RecognitionCallback):
    """阿里云语音识别回调"""

    def on_open(self) -> None:
        print("[ASR] 阿里云连接已建立", flush=True)

    def on_close(self) -> None:
        print("[ASR] 连接已关闭", flush=True)

    def on_complete(self) -> None:
        print("[ASR] 识别完成", flush=True)

    def on_error(self, message) -> None:
        print("[ASR] 错误:", message.message if hasattr(message, 'message') else message, flush=True)

    def on_event(self, result: RecognitionResult) -> None:
        sentence = result.get_sentence()
        if isinstance(sentence, dict) and 'text' in sentence:
            text = sentence['text'].strip()
            is_end = RecognitionResult.is_sentence_end(sentence)
            if text:
                print(f"[ASR] 识别[end={is_end}]: {text}", flush=True)
                _result_queue.put({"text": text, "final": is_end})


def _get_pyaudio():
    global _p
    if _p is None:
        _p = pyaudio.PyAudio()
    return _p


def list_audio_devices():
    """列出音频设备，优先WASAPI，标记loopback设备"""
    p = _get_pyaudio()
    result = []
    try:
        wasapi_info = p.get_host_api_info_by_type(pyaudio.paWASAPI)
        for i in range(p.get_device_count()):
            info = p.get_device_info_by_index(i)
            if info["hostApi"] != wasapi_info["index"]:
                continue
            is_loopback = "[Loopback]" in info["name"]
            is_mic = info["maxInputChannels"] > 0 and not is_loopback
            if is_loopback or is_mic:
                result.append({
                    "index": i,
                    "name": info["name"],
                    "channels": max(info["maxInputChannels"], info["maxOutputChannels"]),
                    "samplerate": int(info["defaultSampleRate"]),
                    "is_loopback": is_loopback,
                })
    except Exception as e:
        print("[ASR] 列设备失败:", e)
    return result


def find_loopback_device():
    """自动查找loopback设备"""
    for dev in list_audio_devices():
        if dev["is_loopback"]:
            return dev["index"]
    return None


def ensure_model():
    """检查阿里云API Key是否配置"""
    return bool(dashscope.api_key and dashscope.api_key != "your_api_key_here")


def _resample_float_to_16k_int16(audio_float, orig_sr):
    """将float32音频重采样到16kHz并转为int16 PCM bytes（供阿里云识别）"""
    if orig_sr != 16000:
        ratio = orig_sr / 16000.0
        new_len = int(len(audio_float) / ratio)
        indices = np.linspace(0, len(audio_float) - 1, new_len)
        audio_float = np.interp(indices, np.arange(len(audio_float)), audio_float)
    audio_float = np.clip(audio_float, -1.0, 1.0)
    return (audio_float * 32767).astype(np.int16).tobytes()


def _read_loop():
    """后台线程：循环读取音频并发送给阿里云识别"""
    global _is_running
    chunk_count = 0
    while _is_running:
        try:
            data = _stream.read(12000, exception_on_overflow=False)
            if not data:
                break
            # 按设备实际声道数解析int16，再转单声道float32
            raw = np.frombuffer(data, dtype=np.int16).astype(np.float32) / 32768.0
            if _channels > 1:
                raw = raw.reshape(-1, _channels).mean(axis=1)
            else:
                raw = raw.reshape(-1)
            raw = np.nan_to_num(raw, nan=0.0, posinf=0.0, neginf=0.0)
            # 音量
            volume = float(np.sqrt(np.mean(raw ** 2)) * 1000) if len(raw) > 0 else 0.0

            # 重采样到16kHz int16 PCM
            pcm_16k = _resample_float_to_16k_int16(raw, _orig_samplerate)

            # 保存音频用于诊断
            if SAVE_AUDIO:
                _recorded_pcm.append(pcm_16k)

            # 分块发送给阿里云（每块约3200字节=100ms，符合推荐）
            if _recognition:
                frame_size = 3200
                for i in range(0, len(pcm_16k), frame_size):
                    _recognition.send_audio_frame(pcm_16k[i:i+frame_size])

            chunk_count += 1
            # 每20块（约5秒）打印一次音量，便于排查
            if chunk_count % 20 == 0:
                print(f"[ASR] 音量监控: {volume:.0f} {'🔊有声音' if volume > 10 else '🔇静音'}", flush=True)
            if chunk_count % 5 == 0:
                _volume_queue.put({"volume": round(volume, 1)})
        except Exception:
            if not _is_running:
                break
            time.sleep(0.1)


def start_capture(device_index=None, on_sentence=None):
    """启动音频捕获和阿里云识别"""
    global _stream, _is_running, _device_index, _read_thread, _orig_samplerate, _recognition, _channels

    if _is_running:
        # 已在运行中，先停止再重启
        stop_capture()
        time.sleep(0.5)

    if not ensure_model():
        return {"ok": False, "msg": "阿里云API Key未配置，请设置LLM_API_KEY环境变量"}

    if device_index is None:
        device_index = find_loopback_device()
        if device_index is None:
            return {"ok": False, "msg": "未找到可用的音频输入设备"}

    _device_index = device_index
    if SAVE_AUDIO:
        _recorded_pcm.clear()

    try:
        p = _get_pyaudio()
        dev_info = p.get_device_info_by_index(device_index)
        _orig_samplerate = int(dev_info["defaultSampleRate"])
        # 使用设备实际声道数（loopback通常是2声道）
        _channels = max(1, int(dev_info.get("maxInputChannels", 2)))

        _stream = p.open(
            format=pyaudio.paInt16,
            channels=_channels,
            rate=_orig_samplerate,
            input=True,
            frames_per_buffer=12000,
            input_device_index=device_index,
        )

        # 创建阿里云识别器
        _recognition = Recognition(
            model=ASR_MODEL,
            format='pcm',
            sample_rate=16000,
            callback=_AsrCallback(),
        )
        _recognition.start()

        _is_running = True
        _read_thread = threading.Thread(target=_read_loop, daemon=True)
        _read_thread.start()

        return {"ok": True, "msg": "已启动阿里云识别: %s" % dev_info["name"], "device": dev_info["name"]}
    except Exception as e:
        return {"ok": False, "msg": "启动失败: %s" % str(e)}


def stop_capture():
    global _stream, _is_running, _read_thread, _recognition
    _is_running = False
    if _stream:
        try:
            _stream.stop_stream()
        except Exception:
            pass
    if _read_thread and _read_thread.is_alive():
        _read_thread.join(timeout=2)
    _read_thread = None
    if _stream:
        try:
            _stream.close()
        except Exception:
            pass
    _stream = None
    # 停止阿里云识别
    if _recognition:
        try:
            _recognition.stop()
        except Exception:
            pass
    _recognition = None
    # 保存录音用于诊断
    if SAVE_AUDIO and _recorded_pcm:
        try:
            import wave
            wav_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "session_record.wav")
            pcm_data = b''.join(_recorded_pcm)
            with wave.open(wav_path, 'wb') as wf:
                wf.setnchannels(1)
                wf.setsampwidth(2)
                wf.setframerate(16000)
                wf.writeframes(pcm_data)
            print(f"[ASR] 会话录音已保存: {wav_path} ({len(pcm_data)/32000:.1f}秒)", flush=True)
        except Exception as e:
            print(f"[ASR] 保存录音失败: {e}", flush=True)
    return {"ok": True, "msg": "已停止"}


def get_results():
    results = []
    while True:
        try:
            results.append(_result_queue.get_nowait())
        except queue.Empty:
            break
    while True:
        try:
            results.append(_volume_queue.get_nowait())
        except queue.Empty:
            break
    return results


def is_running():
    return _is_running


import atexit

@atexit.register
def _cleanup():
    global _is_running, _stream, _recognition
    _is_running = False
    if _stream:
        try:
            _stream.stop_stream()
        except Exception:
            pass
        try:
            _stream.close()
        except Exception:
            pass
    _stream = None
    if _recognition:
        try:
            _recognition.stop()
        except Exception:
            pass
    _recognition = None

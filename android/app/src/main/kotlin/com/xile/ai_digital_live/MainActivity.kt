package com.xile.ai_digital_live

import android.app.Activity
import android.content.Intent
import android.speech.RecognizerIntent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterActivity() {
    private val channelName = "com.xile/speech"
    private var pendingResult: MethodChannel.Result? = null
    private val reqSpeech = 0x51E1

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "recognizeIntent" -> {
                        if (pendingResult != null) {
                            result.error("busy", "语音识别进行中", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                                putExtra(
                                    RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                                    RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
                                )
                                putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.SIMPLIFIED_CHINESE)
                                putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, "zh-CN")
                                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                                putExtra(RecognizerIntent.EXTRA_PROMPT, "请说话，说完点完成")
                            }
                            if (intent.resolveActivity(packageManager) == null) {
                                result.error("unavailable", "本机无语音识别服务", null)
                                return@setMethodCallHandler
                            }
                            pendingResult = result
                            startActivityForResult(intent, reqSpeech)
                        } catch (e: Exception) {
                            pendingResult = null
                            result.error("unavailable", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != reqSpeech) return
        val reply = pendingResult
        pendingResult = null
        if (reply == null) return
        if (resultCode != Activity.RESULT_OK || data == null) {
            reply.success(null)
            return
        }
        val texts = data.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
        reply.success(texts?.firstOrNull())
    }
}

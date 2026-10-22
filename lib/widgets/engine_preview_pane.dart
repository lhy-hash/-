import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../models/digital_human_config.dart';
import '../services/digital_human_engine.dart';
import '../theme/app_theme.dart';

/// 手机端内嵌 WebRTC；电脑后台打开独立预览窗（Edge 应用模式），控台负责驱动口型。
class EnginePreviewPane extends StatefulWidget {
  const EnginePreviewPane({
    super.key,
    required this.engine,
    required this.onSession,
    required this.onError,
    required this.onReady,
    this.onLike,
    this.roomId,
  });

  final DigitalHumanEngine engine;
  final void Function(String sessionId) onSession;
  final void Function(String message) onError;
  final VoidCallback onReady;
  final void Function(Offset localPos)? onLike;
  final String? roomId;

  @override
  State<EnginePreviewPane> createState() => EnginePreviewPaneState();
}

class EnginePreviewPaneState extends State<EnginePreviewPane> {
  WebViewController? _web;
  String? _hint;
  bool _bound = false;
  bool _started = false;
  Timer? _sessionPoll;
  String? _resolvedBase;

  DigitalHumanConfig get _cfg => widget.engine.config;
  bool get _isWindows => !kIsWeb && Platform.isWindows;

  String get _previewUrl {
    final base = _cfg.normalizedBase;
    final rid = widget.roomId ?? '';
    final avatar = Uri.encodeComponent(_cfg.avatarId);
    // 手机用稳定画面，不走 WebRTC，避免黑屏来回闪
    final light = !_isWindows;
    final q = 't=${DateTime.now().millisecondsSinceEpoch}'
        '&avatar=$avatar'
        '${light ? '&mode=mjpeg&fps=18' : ''}'
        '${rid.isNotEmpty ? '&roomId=${Uri.encodeComponent(rid)}' : ''}';
    return '$base/xile_preview.html?$q';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  void dispose() {
    _sessionPoll?.cancel();
    final web = _web;
    _web = null;
    if (web != null) {
      web.runJavaScript('try{window.xileStop&&window.xileStop();}catch(e){}');
      web.loadRequest(Uri.parse('about:blank'));
    }
    widget.engine.onPlayAudio = null;
    super.dispose();
  }

  Future<void> _boot() async {
    try {
      if (_isWindows) {
        await _bootWindowsPreview();
      } else {
        await _bootEmbeddedWebView();
      }
    } catch (e) {
      if (mounted) setState(() => _hint = '$e');
      widget.onError('$e');
    }
  }

  Future<void> _bootWindowsPreview() async {
    widget.onReady();
    await openInBrowser();
    _startSessionPoll();
    if (mounted) {
      setState(() => _hint = '数字人画面在弹出的预览窗中，本页是控台');
    }
  }

  Future<void> _bootEmbeddedWebView() async {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF222222))
      ..addJavaScriptChannel(
        'XileBridge',
        onMessageReceived: (msg) {
          try {
            final data = jsonDecode(msg.message) as Map<String, dynamic>;
            _handleMessage(data);
          } catch (_) {}
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(onPageFinished: (_) async {
          widget.onReady();
          await _connectOnce();
        }),
      );

    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setMediaPlaybackRequiresUserGesture(false);
    }
    // 清缓存，避免旧 MJPEG/大图把 WebView 拖死
    await controller.clearCache();

    if (_cfg.isBaidu) {
      await controller.loadFlutterAsset('assets/web/baidu_bridge.html');
    } else {
      final probe = await _resolveReachableEngine();
      _resolvedBase = probe;
      if (probe != null) {
        widget.engine.config.engineBaseUrl = probe;
        // 关键：用 baseUrl 把本地 HTML 标成引擎同源，彻底避开跨域 Failed to fetch
        final html = await rootBundle.loadString('assets/web/dh_bridge.html');
        await controller.loadHtmlString(html, baseUrl: '$probe/');
        if (mounted) {
          setState(() => _hint = '引擎可达 $probe，正在拉画面…');
        }
      } else {
        final tried = _engineCandidates().join(' · ');
        final msg =
            '手机连不上电脑引擎。已试：$tried。请在应用宝设置里连点「性能」7次打开ADB后，运行桌面「修复喜乐连接.bat」';
        widget.onError(msg);
        if (mounted) setState(() => _hint = msg);
        // 仍加载页面，方便用户看到 HUD
        final html = await rootBundle.loadString('assets/web/dh_bridge.html');
        await controller.loadHtmlString(
          html,
          baseUrl: 'http://127.0.0.1:8010/',
        );
      }
    }
    if (!mounted) return;
    setState(() => _web = controller);
    widget.engine.jsSpeakDriver = _speakViaJs;
    widget.engine.onPlayAudio = (url, [int? syncDelayMs]) async {
      final delay = syncDelayMs ?? 80;
      final interrupt = widget.engine.takePlayInterrupt();
      await _web?.runJavaScript(
        'window.xilePlay && window.xilePlay(${jsonEncode(url)}, $delay, ${interrupt ? 'true' : 'false'});',
      );
    };
  }

  List<String> _engineCandidates() {
    return <String>[
      // 手机开热点、电脑连手机：电脑 IP 通常是热点网段
      // WebRTC 媒体是 UDP，必须走热点局域网，不能依赖 adb reverse
      'http://127.0.0.1:8010',
      'http://172.20.10.5:8010', // iPhone 热点网段
      'http://192.168.100.103:8010',
      'http://192.168.40.241:8010',
      'http://192.168.156.212:8010',
      _cfg.normalizedBase,
      'http://172.29.32.1:8010',
      'http://10.0.2.2:8010',
      'http://127.0.0.1:8010',
    ];
  }

  /// 从应用宝/手机探测本机引擎可达地址
  Future<String?> _resolveReachableEngine() async {
    final seen = <String>{};
    for (final raw in _engineCandidates()) {
      final u = raw.replaceAll(RegExp(r'/$'), '');
      if (u.isEmpty || !seen.add(u)) continue;
      try {
        final res = await http
            .get(Uri.parse('$u/'))
            .timeout(const Duration(seconds: 2));
        if (res.statusCode >= 200 && res.statusCode < 500) return u;
      } catch (_) {}
    }
    return null;
  }

  void _handleMessage(Map<String, dynamic> data) {
    if (data['type'] == 'session' && data['sessionid'] != null) {
      _bound = true;
      widget.onSession('${data['sessionid']}');
      if (mounted) setState(() => _hint = null);
    } else if (data['type'] == 'error') {
      widget.onError('${data['message']}');
      if (mounted) setState(() => _hint = '${data['message']}');
    } else if (data['type'] == 'audioStarted') {
      widget.engine.notifyAudioStarted();
    } else if (data['type'] == 'audioEnded') {
      widget.engine.notifyAudioEnded();
    } else if (data['type'] == 'like') {
      final dx = (data['x'] as num?)?.toDouble() ?? 0;
      final dy = (data['y'] as num?)?.toDouble() ?? 0;
      widget.onLike?.call(Offset(dx, dy));
      // 点赞也算用户手势，顺便开声
      unawaited(setMuted(false));
    }
  }

  void _startSessionPoll() {
    _sessionPoll?.cancel();
    _sessionPoll = Timer.periodic(const Duration(seconds: 2), (_) async {
      final ok = await widget.engine.ensureSession(forceRefresh: !_bound);
      if (ok && widget.engine.sessionId != null) {
        _bound = true;
        widget.onSession(widget.engine.sessionId!);
        if (mounted) {
          setState(() => _hint = '数字人已连接 · 请看预览窗里的画面');
        }
      }
    });
  }

  Future<void> _connectOnce() async {
    if (_started) return;
    _started = true;
    await reconnect();
  }

  Future<void> reconnect() async {
    _bound = false;
    if (_isWindows) {
      await openInBrowser();
      _startSessionPoll();
      return;
    }

    if (_cfg.isBaidu) {
      if (!_cfg.baiduReady) {
        setState(() => _hint = '请到「设置」填写百度曦灵 AppID / AppKey');
        widget.onError('请先在设置填写百度曦灵 AppID / AppKey');
        return;
      }
      _started = true;
      setState(() => _hint = null);
      try {
        final token = _cfg.buildBaiduToken();
        final cfg = {
          'token': token,
          'figureId': _cfg.baiduFigureId,
          'cameraId': _cfg.baiduCameraId,
          'tts': _cfg.baiduTtsMap(),
        };
        await _web?.runJavaScript(
          'window.xileConnect && window.xileConnect(${jsonEncode(cfg)});',
        );
      } catch (e) {
        widget.onError('$e');
      }
      return;
    }

    _started = true;
    final base = _resolvedBase ?? _cfg.normalizedBase;
    setState(() => _hint = '正在连接数字人画面… $base');
    await _web?.runJavaScript(
      "window.xileConnect && window.xileConnect(${jsonEncode(base)}, ${jsonEncode(_cfg.avatarId.isNotEmpty ? _cfg.avatarId : 'user_upload_host')});",
    );
  }

  Future<bool> _speakViaJs(String text, {required bool interrupt}) async {
    if (!_cfg.isBaidu) return false;
    final token = _cfg.buildBaiduToken();
    final tts = _cfg.baiduTtsMap();
    await _web?.runJavaScript(
      'window.xileSpeak && window.xileSpeak(${jsonEncode(text)}, ${interrupt ? 'true' : 'false'}, ${jsonEncode(token)}, ${jsonEncode(tts)});',
    );
    return true;
  }

  Future<void> setMuted(bool muted) async {
    await _web?.runJavaScript(
      'window.xileSetMuted && window.xileSetMuted(${muted ? 'true' : 'false'});',
    );
  }

  /// 说话时提高画面刷新，静音时降到 1fps，避免进房就卡死
  Future<void> setActive(bool active) async {
    await _web?.runJavaScript(
      'window.xileSetActive && window.xileSetActive(${active ? 'true' : 'false'});',
    );
  }

  Future<void> openInBrowser() async {
    // 控台用 MJPEG，避免再开一路 WebRTC 和手机抢 GPU/带宽
    final url = 'http://127.0.0.1:8010/xile_preview.html'
        '?mode=mjpeg&fps=18'
        '&t=${DateTime.now().millisecondsSinceEpoch}'
        '&avatar=${Uri.encodeComponent(_cfg.avatarId)}'
        '${(widget.roomId ?? '').isNotEmpty ? '&roomId=${Uri.encodeComponent(widget.roomId!)}' : ''}';
    final edge = [
      r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
      r'C:\Program Files\Microsoft\Edge\Application\msedge.exe',
    ].firstWhere((p) => File(p).existsSync(), orElse: () => '');
    if (edge.isNotEmpty) {
      await Process.start(edge, [
        '--app=$url',
        '--window-size=720,1280',
        '--new-window',
      ]);
    } else {
      await Process.start('cmd', ['/c', 'start', '', url], runInShell: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isWindows) {
      final connected = widget.engine.connected;
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              connected ? Icons.face_retouching_natural : Icons.live_tv,
              color: connected ? AppColors.accent : AppColors.brand,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              connected ? '数字人已连接' : '本地数字人控台',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              _hint ??
                  (connected
                      ? '画面在 Edge 预览窗，本页负责开播与问答'
                      : '点击下方可重新打开预览窗'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: openInBrowser,
              child: const Text('打开数字人画面'),
            ),
          ],
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        if (_web != null)
          WebViewWidget(controller: _web!)
        else
          const ColoredBox(color: Colors.black),
        if (_cfg.isBaidu && !_cfg.baiduReady)
          Container(
            color: Colors.black.withValues(alpha: 0.72),
            alignment: Alignment.center,
            padding: const EdgeInsets.all(24),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person_outline, color: Colors.white, size: 56),
                SizedBox(height: 14),
                Text(
                  '要站着/坐着真人直播，请配置百度曦灵',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  '设置 → 选「百度曦灵 · 实时直播」→ 填写 AppID / AppKey\n'
                  '形象默认全身站姿。口播声音已用通义真人音色。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, height: 1.45),
                ),
              ],
            ),
          )
        else if (_hint != null &&
            (_hint!.contains('失败') ||
                _hint!.contains('连不上') ||
                _hint!.contains('填写')))
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Text(
              _hint!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../app_role.dart';
import '../models/content_factory.dart';
import '../models/host_presence_profile.dart';
import '../models/host_voice_profile.dart';
import '../models/live_chat_message.dart';
import '../services/digital_human_engine.dart';
import '../services/llm_service.dart';
import '../services/room_sync_service.dart';
import '../services/voice_service.dart';

enum AvatarMotion { idle, speaking, wave, nod, point }

/// 照片生成数字人 + 边讲话术边答问 + 后台/手机同步
class LiveRoomController extends ChangeNotifier {
  LiveRoomController({
    required this.llm,
    required this.engine,
    VoiceService? voice,
    AppRole? role,
  })  : voice = voice ?? VoiceService(),
        role = role ?? resolveAppRole();

  final LlmService llm;
  final DigitalHumanEngine engine;
  final VoiceService voice;
  final AppRole role;
  final ImagePicker _picker = ImagePicker();
  final _rng = math.Random();

  late RoomSyncService sync = RoomSyncService(baseUrl: engine.config.engineBaseUrl);
  Timer? _syncTimer;

  final List<LiveChatMessage> messages = [];
  final Map<String, String> presetReplies = {};
  final List<String> _scriptQueue = [];
  final List<_PendingQuestion> _questionQueue = [];
  PreparedTcp? _aheadClip;
  String? _aheadSpoken;
  bool _scriptNeedsHardStart = true;
  final Set<String> _seenAskIds = {};
  final Set<String> _seenSyncMsgIds = {};

  String roomId = '';
  String? avatarPath;
  String avatarName = '小乐';
  String productName = '';
  String productPrice = '';
  String productContext =
      '喜乐鲜味礼盒，直播间九九元，食材扎实、做法省事、分量够分享、家常鲜香，价格以挂链为准。';
  String roomTitle = '喜乐直播间';
  String hostScript = '';
  List<String> scriptVariants = [];
  int _scriptVariantIndex = 0;
  bool loopNarration = true;
  int viewerCount = 0;
  int likeCount = 0;
  String viewerId = '';
  bool roomLive = false;
  bool busy = false;
  bool aiSpeaking = false;
  bool userListening = false;
  bool voiceCancelArmed = false;
  bool narrating = false;
  bool creatingAvatar = false;
  int avatarProgress = 0;
  String listenHint = '';
  String createHint = '';
  AvatarMotion motion = AvatarMotion.idle;
  String? error;
  String statusLine = '未连接真实数字人引擎';

  /// 形象变更 / 同步后需要重连 WebRTC
  VoidCallback? onAvatarReady;

  /// 听语音时静音预览流，避免抢麦
  Future<void> Function(bool muted)? onPreviewMute;

  bool get isAdmin => role == AppRole.admin;
  bool get isClient => role == AppRole.client;
  bool get isRealEngine => engine.config.enabled && engine.connected;

  HostVoiceProfile get voiceProfile => voice.profile;

  void _syncCloudAsr() {
    // 只要有通义 Key 就用真人 TTS / 云识别（不依赖演示开关）
    final key = llm.apiKey.trim();
    voice.cloudAsr.configure(
      llmApiKey: key,
      llmBaseUrl: llm.baseUrl,
      llmProviderId: llm.providerId,
      baiduApiKey: engine.config.baiduAsrApiKey,
      baiduSecretKey: engine.config.baiduAsrSecretKey,
      engineBaseUrl: engine.config.normalizedBase,
    );
    voice.cloudTts.configure(
      apiKey: key,
      voice: voice.profile.qwenVoice,
    );
    // 统一音频出口：Qwen 合成后也走 webview 播，口型同步生效，不会两种声音同响
    voice.webPlayer = (url, [delay]) async {
      await engine.onPlayAudio?.call(url, delay);
    };
  }

  Future<void> refreshHostVoice() => _syncHostVoice();

  Future<void> _syncHostVoice() async {
    _syncCloudAsr();
    // 以当前 avatarId / 房间为准，禁止把所有房间拧成同一个形象
    final presence = HostPresenceProfile.byAvatarId(engine.config.avatarId) ??
        HostPresenceProfile.byId(engine.config.hostPresenceId);
    if (presence != null) {
      engine.config.hostPresenceId = presence.id;
      // 只在 avatar 空时才回填；绝不覆盖房间已选形象
      if (engine.config.avatarId.trim().isEmpty) {
        engine.config.avatarId = presence.avatarId;
      }
      if (engine.config.voiceProfileId.trim().isEmpty) {
        engine.config.voiceProfileId = presence.voiceProfileId;
      }
    }
    final profile = HostVoiceProfile.resolve(
      hostName: avatarName,
      avatarId: engine.config.avatarId,
      roomId: roomId,
      preferredId: engine.config.voiceProfileId.isNotEmpty
          ? engine.config.voiceProfileId
          : null,
    );
    final locked = _lockVoiceGender(
      profile,
      HostPresenceProfile.byAvatarId(engine.config.avatarId) ?? presence,
    );
    engine.config.voiceProfileId = locked.id;
    await voice.applyProfile(locked);
    voice.cloudTts.configure(voice: locked.qwenVoice);
    engine.config.baiduTtsPer = locked.baiduPer;
    engine.config.baiduTtsSpd = locked.baiduSpd;
    engine.config.baiduTtsPit = locked.baiduPit;
    engine.config.baiduTtsVol = locked.baiduVol;
  }

  HostVoiceProfile _lockVoiceGender(
    HostVoiceProfile profile,
    HostPresenceProfile? presence,
  ) {
    if (presence == null) return profile;
    if (presence.isMale && profile.gender != VoiceGender.male) {
      return HostVoiceProfile.byId('ale_steady')!;
    }
    if (presence.isFemale && profile.gender != VoiceGender.female) {
      return HostVoiceProfile.byId(presence.voiceProfileId) ??
          HostVoiceProfile.byId('mei_bright')!;
    }
    return profile;
  }

  /// 切换站立/坐播形象（仅设置页手动切换时覆盖当前房间形象）
  Future<void> applyPresence(HostPresenceProfile presence) async {
    engine.config.hostPresenceId = presence.id;
    engine.config.avatarId = presence.avatarId;
    engine.config.voiceProfileId = presence.voiceProfileId;
    avatarName = presence.label.split('·').first.trim();
    if (avatarName.isEmpty) {
      avatarName = presence.isMale ? '阿乐' : '小美';
    }
    await _syncHostVoice();
    _refreshStatus();
    notifyListeners();
    onAvatarReady?.call();
    if (isAdmin) unawaited(_publishRoom());
  }

  Future<void> init() async {
    await voice.init();
    // 口播音色绑定：引擎 EdgeTTS 用当前主播 profile
    engine.ttsPayloadBuilder = () => voice.profile.toEngineTts();
    await _syncHostVoice();
    sync.baseUrl = engine.config.normalizedBase;
    if (messages.isEmpty) {
      messages.add(
        LiveChatMessage(
          id: 'sys1',
          role: ChatRole.system,
          text: isClient
              ? '请先登录并选择直播间。进房后数字人会持续讲解货品，也可文字/语音提问。'
              : '请先选择要控台的直播间。可上传照片更换数字人形象，开播后持续讲解并与手机预览同步。',
          inputType: ChatInputType.text,
        ),
      );
    }
    if (hostScript.isEmpty) {
      hostScript = _defaultScript();
    }
    _refreshStatus();
    _startSyncLoop();
    notifyListeners();
  }

  /// 从大厅进入指定直播间
  Future<void> enterRoom(SyncRoomState room) async {
    await leaveRoom(silent: true);
    roomId = room.id;
    sync.roomId = room.id;
    roomTitle = room.title;
    avatarName = room.hostName.isNotEmpty ? room.hostName : avatarName;
    productName = room.productName;
    productPrice = room.productPrice;
    productContext = room.productContext.isNotEmpty
        ? room.productContext
        : productContext;
    scriptVariants = room.scriptVariants.isNotEmpty
        ? List<String>.from(room.scriptVariants)
        : (room.hostScript.isNotEmpty
            ? [room.hostScript]
            : [_defaultScript()]);
    _scriptVariantIndex = 0;
    hostScript = scriptVariants.first;
    roomLive = room.live;
    viewerCount = room.viewerCount;
    likeCount = room.likeCount;
    if (room.avatarId.isNotEmpty) {
      // 热点稳定版：始终用上传视频人物，防止房间配置被改回 dh_xixi 导致封面是人对了、进房又换掉
      var aid = room.avatarId;
      if (aid == 'dh_xixi' || aid.isEmpty) {
        aid = 'user_upload_host';
      }
      engine.config.avatarId = aid;
      if (aid == 'user_upload_host' || aid == 'host_upload') {
        engine.config.avatarId = 'user_upload_host';
        engine.config.hostPresenceId = 'host_upload';
      } else {
        final p = HostPresenceProfile.byAvatarId(engine.config.avatarId);
        if (p != null) engine.config.hostPresenceId = p.id;
      }
    } else {
      engine.config.avatarId = 'user_upload_host';
      engine.config.hostPresenceId = 'host_upload';
    }
    // 二次审核：房间指定音色优先；否则清空后按形象/主播名绑定
    engine.config.voiceProfileId = room.voiceProfileId;
    messages
      ..clear();
    // 进房欢迎不进公屏，只保留之后的提问与回答
    _seenAskIds.clear();
    _seenSyncMsgIds.clear();
    _scriptQueue.clear();
    _questionQueue.clear();
    error = null;
    await _syncHostVoice();
    _refreshStatus();
    notifyListeners();
    onAvatarReady?.call();

    roomLive = room.live;
    await _publishRoom();
    viewerId = 'v-${DateTime.now().millisecondsSinceEpoch}-${_rng.nextInt(9999)}';
    final presence = await sync.reportPresence(
      action: 'join',
      viewerId: viewerId,
      id: roomId,
    );
    if (presence != null) {
      viewerCount = presence.viewerCount;
      likeCount = presence.likeCount;
      notifyListeners();
    }
    // 等画面就绪再开口；只打断旧句，不再狂清队列把渲染冲死
    if (isClient) {
      roomLive = true;
      unawaited(() async {
        try {
          await engine.interrupt();
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 800));
        if (!roomLive || roomId.isEmpty) return;
        await onPreviewMute?.call(false);
        // 再点一次开声，避开 WebView 首句被静音策略吞掉
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await onPreviewMute?.call(false);
        await startNarration(loop: true);
      }());
    }
  }

  /// 退出直播间：停讲解、打断引擎口型、静音预览
  Future<void> leaveRoom({bool silent = false}) async {
    final leavingId = roomId;
    final leavingViewer = viewerId;
    roomLive = false;
    narrating = false;
    loopNarration = false;
    busy = false;
    aiSpeaking = false;
    userListening = false;
    listenHint = '';
    _scriptQueue.clear();
    _questionQueue.clear();
    _aheadClip = null;
    _aheadSpoken = null;
    _scriptNeedsHardStart = true;
    motion = AvatarMotion.idle;
    // 先停手机正在放的声音，再做别的。否则后到的音频会在退出后接着响。
    try {
      await engine.interrupt();
    } catch (_) {}
    try {
      await voice.stopSpeaking();
    } catch (_) {}
    try {
      await voice.stopListen();
    } catch (_) {}
    await onPreviewMute?.call(true);
    if (leavingId.isNotEmpty && leavingViewer.isNotEmpty) {
      await sync.reportPresence(
        action: 'leave',
        viewerId: leavingViewer,
        id: leavingId,
      );
    }
    if (!silent) {
      statusLine = '已退出直播间';
      notifyListeners();
    }
    roomId = '';
    viewerId = '';
    sync.roomId = null;
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  String _defaultScript() {
    return '''
家人们好，跟大家说一声哈，我是AI数字人$avatarName。
今天给大家带来喜乐鲜味礼盒。
直播间价九十九元，到手就这个价。
食材很扎实，做法也省事。
分量够一家人分享，家常鲜香。
觉得划算的家人们，扣个1。
想要的扣想要，我看着给大家上链接。
价格和规格，以商品页为准哦。
''';
  }

  void _startSyncLoop() {
    _syncTimer?.cancel();
    // 观众端 4 秒一同步，减轻进房卡顿
    final every = isClient ? const Duration(milliseconds: 1500) : const Duration(seconds: 2);
    _syncTimer = Timer.periodic(every, (_) {
      unawaited(_tickSync());
    });
    unawaited(_tickSync());
  }

  Future<void> _tickSync() async {
    if (!engine.config.enabled) return;
    sync.baseUrl = engine.config.normalizedBase;
    try {
      if (isAdmin) {
        await _publishRoom();
        await _pullRemoteAsks();
      } else {
        await _pullRoomAsClient();
        await _pullRemoteAsks();
      }
    } catch (_) {}
  }

  Future<void> _publishRoom() async {
    if (roomId.isEmpty) return;
    // 公屏只同步观众提问与针对提问的回答，不含讲解步骤
    final msgs = messages
        .where((m) => m.isUser || m.isAi)
        .take(30)
        .map((m) {
      return {
        'id': m.id,
        'role': m.role.name,
        'text': m.text,
        'ts': DateTime.now().millisecondsSinceEpoch,
      };
    }).toList();
    await sync.publishRoom(
      id: roomId,
      avatarId: engine.config.avatarId,
      voiceProfileId: engine.config.voiceProfileId,
      live: roomLive,
      title: roomTitle,
      statusLine: statusLine,
      adminSessionId: isAdmin ? engine.sessionId : null,
      hostName: avatarName,
      productName: productName,
      productPrice: productPrice,
      productContext: productContext,
      hostScript: hostScript,
      messages: msgs,
    );
  }

  Future<void> _pullRoomAsClient() async {
    if (roomId.isEmpty) return;
    final room = await sync.fetchRoom(id: roomId);
    if (room == null) return;

    var needReconnect = false;
    if (room.avatarId.isNotEmpty && room.avatarId != engine.config.avatarId) {
      engine.config.avatarId = room.avatarId;
      needReconnect = true;
    }
    if (room.voiceProfileId.isNotEmpty &&
        room.voiceProfileId != engine.config.voiceProfileId) {
      engine.config.voiceProfileId = room.voiceProfileId;
      unawaited(_syncHostVoice());
    } else if (needReconnect) {
      // 形象变了但未带音色：按新形象重新绑定
      engine.config.voiceProfileId = '';
      unawaited(_syncHostVoice());
    }
    if (room.title.isNotEmpty && room.title != roomTitle) {
      roomTitle = room.title;
    }
    if (room.hostName.isNotEmpty) avatarName = room.hostName;
    if (room.productContext.isNotEmpty) productContext = room.productContext;
    if (room.productName.isNotEmpty) productName = room.productName;
    if (room.productPrice.isNotEmpty) productPrice = room.productPrice;
    if (room.hostScript.isNotEmpty && !narrating) {
      hostScript = room.hostScript;
    }
    if (room.live != roomLive) {
      roomLive = room.live;
    }
    if (room.statusLine.isNotEmpty) {
      statusLine = room.statusLine;
    }
    if (room.likeCount != likeCount) likeCount = room.likeCount;
    viewerCount = room.viewerCount;

    for (final m in room.messages) {
      if (m.id.isEmpty || _seenSyncMsgIds.contains(m.id)) continue;
      _seenSyncMsgIds.add(m.id);
      if (messages.any((x) => x.id == m.id || x.text == m.text)) continue;
      final role = switch (m.role) {
        'ai' => ChatRole.ai,
        'user' => ChatRole.user,
        _ => ChatRole.system,
      };
      messages.insert(
        0,
        LiveChatMessage(
          id: m.id,
          role: role,
          text: m.text,
          inputType: ChatInputType.text,
        ),
      );
      if (role == ChatRole.ai) {
        unawaited(onPreviewMute?.call(false) ?? Future.value());
      }
    }

    if (needReconnect) {
      onAvatarReady?.call();
    }
    notifyListeners();
  }

  Future<void> _pullRemoteAsks() async {
    if (roomId.isEmpty) return;
    // 远端提问一律进队列，由口播循环串行：打断讲解 → 回答 → 继续讲商品
    final asks = await sync.pendingAsks(id: roomId);
    for (final a in asks) {
      if (_seenAskIds.contains(a.id)) continue;
      _seenAskIds.add(a.id);
      messages.insert(
        0,
        LiveChatMessage(
          id: a.id,
          role: ChatRole.user,
          text: a.text,
          inputType: ChatInputType.text,
        ),
      );
      notifyListeners();
      await _enqueueQuestion(
        a.text,
        askId: a.id,
        roomIdOverride: a.roomId.isNotEmpty ? a.roomId : roomId,
      );
    }
  }

  Future<bool> _speakSynced(
    String text, {
    required bool interrupt,
    String? clientSid,
    String? previewSid,
    String? adminSid,
  }) async {
    final room = await sync.fetchRoom(id: roomId);
    final ids = <String>[
      if ((clientSid ?? '').isNotEmpty) clientSid!,
      if ((previewSid ?? '').isNotEmpty) previewSid!,
      if ((adminSid ?? '').isNotEmpty) adminSid!,
      if ((room?.clientSessionId ?? '').isNotEmpty) room!.clientSessionId,
      if ((room?.previewSessionId ?? '').isNotEmpty) room!.previewSessionId,
      if ((room?.adminSessionId ?? '').isNotEmpty) room!.adminSessionId,
      if ((engine.sessionId ?? '').isNotEmpty) engine.sessionId!,
    ];
    var driven = await engine.speakToSessions(
      text,
      sessionIds: ids,
      interrupt: interrupt,
    );
    if (!driven) {
      driven = await engine.speakAll(text, interrupt: interrupt);
    }
    return driven;
  }

  void _refreshStatus() {
    if (creatingAvatar) {
      statusLine = '正在用照片生成数字人 $avatarProgress%';
    } else if (narrating) {
      statusLine = '正在讲解 · ${voice.profile.label}';
    } else if (!engine.config.enabled) {
      statusLine = '演示音色 · ${voice.profile.label}';
    } else if (engine.connected) {
      statusLine = isClient
          ? '直播中 · ${voice.profile.label}'
          : '真实数字人已连接 · ${voice.profile.label}';
    } else {
      statusLine = isClient ? '连接中…' : '引擎已配置，等待画面连接…';
    }
  }

  void onEngineSession(String sessionId) {
    engine.bindSession(sessionId);
    sync.baseUrl = engine.config.normalizedBase;
    if (roomId.isNotEmpty) {
      final role = isClient ? 'client' : 'preview';
      unawaited(sync.reportClientSession(sessionId, role: role, id: roomId));
    }
    _refreshStatus();
    error = null;
    notifyListeners();
    if (isAdmin) unawaited(_publishRoom());
  }

  void onEngineError(String message) {
    error = message;
    engine.clearSession();
    _refreshStatus();
    notifyListeners();
  }

  void setHostScript(String script) {
    hostScript = script.trim();
    notifyListeners();
  }

  /// 相册/拍照 → 上传引擎生成数字人（仅后台）
  Future<void> createDigitalHumanFromPhoto({required bool fromCamera}) async {
    if (!isAdmin) {
      error = '请在电脑后台生成数字人形象';
      notifyListeners();
      return;
    }
    if (!engine.config.enabled) {
      error = '请先在设置开启真实数字人引擎，并保证电脑引擎在线';
      notifyListeners();
      return;
    }
    if (creatingAvatar) return;

    try {
      final file = await _picker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 90,
        maxWidth: 1600,
      );
      if (file == null) return;

      avatarPath = file.path;
      creatingAvatar = true;
      avatarProgress = 0;
      createHint = '正在上传照片并生成数字人…';
      error = null;
      _refreshStatus();
      notifyListeners();

      final avatarId = 'user_photo_${DateTime.now().millisecondsSinceEpoch}';
      final taskId = await engine.createAvatarFromPhoto(
        imagePath: file.path,
        avatarId: avatarId,
        imgSize: 256,
      );
      final result = await engine.waitAvatarTask(
        taskId,
        onProgress: (st) {
          avatarProgress = st.progress.clamp(0, 100);
          createHint = st.isFailed
              ? st.errorMsg
              : '生成中 ${st.progress}% · ${st.status}';
          _refreshStatus();
          notifyListeners();
        },
      );

      creatingAvatar = false;
      if (result.isFailed) {
        error = result.errorMsg.isEmpty ? '生成失败' : result.errorMsg;
        createHint = error!;
        _refreshStatus();
        notifyListeners();
        return;
      }

      engine.config.avatarId = avatarId;
      avatarProgress = 100;
      await _syncHostVoice();
      createHint = '数字人已生成，正在切换出镜形象…';
      _refreshStatus();
      notifyListeners();
      await _publishRoom();

      onAvatarReady?.call();
      await _announce(
        '家人们好，我已经换成你们上传的形象啦。本场主播是人工智能技术生成的数字人，开始讲解或提问都可以。',
        interrupt: true,
        showInChat: false,
      );
    } catch (e) {
      creatingAvatar = false;
      error = e.toString();
      createHint = error!;
      _refreshStatus();
      notifyListeners();
    }
  }

  Future<void> startRoom() async {
    roomLive = true;
    motion = AvatarMotion.speaking;
    notifyListeners();
    await _publishRoom();
    final useOriginal = engine.config.enabled &&
        (engine.config.avatarId == 'user_upload_host' ||
            engine.config.hostPresenceId == 'host_upload');
    if (useOriginal) {
      // 开播：先播视频原声口型，再进入 15 分钟带货口播循环
      aiSpeaking = true;
      motion = AvatarMotion.speaking;
      notifyListeners();
      final ok = await engine.playOriginalVoice(interrupt: true);
      if (ok) {
        await _waitEngineSpeech(maxSeconds: 36);
      } else {
        await _announce(
          '直播间已开启。跟大家说一声哈，我是AI数字人$avatarName，今天给大家带来${productName.isEmpty ? "喜乐鲜味礼盒" : productName}，直播间价${productPrice.isEmpty ? "九十九元" : productPrice}。',
          interrupt: true,
          showInChat: false,
        );
      }
    } else {
      // 不再调用引擎 set_audiotype：会抢占 TTS 通道导致「说一句就停」
      await _announce(
        '直播间已开启。跟大家说一声哈，我是AI数字人$avatarName，今天给大家带来${productName.isEmpty ? "喜乐鲜味礼盒" : productName}，直播间价${productPrice.isEmpty ? "九十九元" : productPrice}。',
        interrupt: true,
        showInChat: false,
      );
    }
    if (!narrating) {
      startNarration(loop: true);
    }
  }

  Future<void> _waitEngineSpeech({int maxSeconds = 36}) async {
    final rounds = (maxSeconds * 1000 / 350).round().clamp(4, 200);
    for (var i = 0; i < rounds; i++) {
      if (!roomLive) break;
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final speaking = await engine.isSpeaking();
      if (speaking == false && i > 4) break;
    }
    aiSpeaking = false;
    motion = AvatarMotion.idle;
    notifyListeners();
  }

  void stopRoom() {
    roomLive = false;
    narrating = false;
    loopNarration = false;
    _scriptQueue.clear();
    _questionQueue.clear();
    _aheadClip = null;
    _aheadSpoken = null;
    _scriptNeedsHardStart = true;
    motion = AvatarMotion.idle;
    aiSpeaking = false;
    unawaited(voice.stopSpeaking());
    unawaited(engine.interrupt());
    _refreshStatus();
    notifyListeners();
    unawaited(_publishRoom());
  }

  Future<void> startNarration({bool loop = true}) async {
    if (narrating) {
      loopNarration = loop;
      if (!busy) unawaited(_runSpeakLoop());
      return;
    }
    // 手机观众端也要持续口播；后台控台在线时由后台主导即可，这里不硬拦截
    if (scriptVariants.isEmpty) {
      scriptVariants = [
        hostScript.trim().isEmpty ? _defaultScript() : hostScript,
      ];
    }
    _scriptVariantIndex = 0;
    hostScript = scriptVariants[_scriptVariantIndex];
    final parts = _splitScript(hostScript);
    if (parts.isEmpty) return;

    loopNarration = loop;
    narrating = true;
    _scriptNeedsHardStart = true;
    _scriptQueue
      ..clear()
      ..addAll(parts);
    _refreshStatus();
    notifyListeners();
    unawaited(_runSpeakLoop());
  }

  void stopNarration() {
    narrating = false;
    loopNarration = false;
    _scriptQueue.clear();
    unawaited(engine.interrupt());
    unawaited(voice.stopSpeaking());
    unawaited(onPreviewMute?.call(true) ?? Future.value());
    _refreshStatus();
    notifyListeners();
  }

  List<String> _splitScript(String script) {
    final raw = script
        .replaceAll('\r\n', '\n')
        .split(RegExp(r'[\n。！？]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    // 合并短句，大幅减少 speak_tcp 次数（进房卡顿主因）
    if (raw.isEmpty) return raw;
    final chunks = <String>[];
    final buf = StringBuffer();
    var count = 0;
    for (final line in raw) {
      if (buf.isNotEmpty) buf.write('，');
      buf.write(line);
      count++;
      if (count >= 3 || buf.length >= 90) {
        chunks.add(buf.toString());
        buf.clear();
        count = 0;
      }
    }
    if (buf.isNotEmpty) chunks.add(buf.toString());
    return chunks;
  }

  Future<void> sendText(String text) async {
    final content = text.trim();
    if (content.isEmpty) return;
    messages.insert(
      0,
      LiveChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: ChatRole.user,
        text: content,
        inputType: ChatInputType.text,
      ),
    );
    notifyListeners();
    String? askId;
    if (isClient) {
      askId = await sync.submitAsk(content, source: 'text');
      if (askId != null) _seenAskIds.add(askId);
    }
    unawaited(onPreviewMute?.call(false) ?? Future.value());
    statusLine = '正在回答你的问题…';
    _refreshStatus();
    notifyListeners();
    await _enqueueQuestion(content, askId: askId);
  }

  Future<void> beginVoiceHold() async {
    if (userListening) return;
    error = null;
    _syncCloudAsr();
    await voice.init();
    userListening = true;
    voiceCancelArmed = false;
    listenHint = '松手发送 · 上滑取消';
    notifyListeners();
    if (aiSpeaking) {
      await voice.stopSpeaking();
      await engine.interrupt();
    }
    try {
      await onPreviewMute?.call(true);
      await voice.startHoldRecord(
        onPartial: (p) {
          listenHint = p.isEmpty ? '松手发送 · 上滑取消' : p;
          notifyListeners();
        },
      );
    } catch (e) {
      userListening = false;
      listenHint = '';
      await onPreviewMute?.call(false);
      final raw = e.toString().replaceFirst('Exception: ', '').trim();
      error = raw.isEmpty ? '无法开始录音' : raw;
      notifyListeners();
      _resumeProductNarration();
      rethrow;
    }
  }

  void setVoiceCancelArmed(bool armed) {
    if (!userListening || voiceCancelArmed == armed) return;
    voiceCancelArmed = armed;
    listenHint = armed ? '松开手指，取消发送' : '松手发送 · 上滑取消';
    notifyListeners();
  }

  Future<void> cancelVoiceHold() async {
    if (!userListening) return;
    try {
      await voice.cancelHoldRecord();
    } catch (_) {}
    userListening = false;
    voiceCancelArmed = false;
    listenHint = '';
    error = null;
    await onPreviewMute?.call(false);
    notifyListeners();
    _resumeProductNarration();
  }

  Future<void> endVoiceHold() async {
    if (!userListening) return;
    if (voiceCancelArmed) {
      await cancelVoiceHold();
      return;
    }
    listenHint = '正在识别…';
    notifyListeners();
    try {
      final heard = await voice.finishHoldRecord(
        onPartial: (p) {
          listenHint = p.isEmpty ? '正在识别…' : p;
          notifyListeners();
        },
      );
      if (heard == null || heard.isEmpty) {
        error = '没有听清，请靠近麦克风再说一次';
        notifyListeners();
        return;
      }
      messages.insert(
        0,
        LiveChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          role: ChatRole.user,
          text: heard,
          inputType: ChatInputType.voice,
        ),
      );
      notifyListeners();
      String? askId;
      if (isClient) {
        askId = await sync.submitAsk(heard, source: 'voice');
        if (askId != null) _seenAskIds.add(askId);
      }
      statusLine = '正在回答你的问题…';
      _refreshStatus();
      notifyListeners();
      await _enqueueQuestion(heard, askId: askId);
    } catch (e) {
      final raw = e.toString().replaceFirst('Exception: ', '').trim();
      if (raw.contains('太短')) {
        error = '说话时间太短';
      } else if (raw.contains('引擎') ||
          raw.contains('通义') ||
          raw.contains('API Key') ||
          raw.contains('云端')) {
        error = raw;
      } else {
        error = raw.isEmpty ? '语音识别失败，请改用文字提问' : raw;
      }
      notifyListeners();
    } finally {
      userListening = false;
      voiceCancelArmed = false;
      listenHint = '';
      await onPreviewMute?.call(false);
      notifyListeners();
      _resumeProductNarration();
    }
  }

  /// 兼容旧单击入口（内部仍走按住录音约 4 秒）
  Future<void> sendVoice() async {
    if (userListening) return;
    try {
      await beginVoiceHold();
      await Future<void>.delayed(const Duration(seconds: 4));
      if (userListening) await endVoiceHold();
    } catch (_) {}
  }

  /// 直播中始终续讲商品：答完用户 / 语音失败后都走这里
  void _resumeProductNarration() {
    if (!roomLive) return;
    loopNarration = true;
    if (_scriptQueue.isEmpty) {
      final parts = _splitScript(
        hostScript.trim().isEmpty
            ? (scriptVariants.isNotEmpty
                ? scriptVariants[_scriptVariantIndex % scriptVariants.length]
                : _defaultScript())
            : hostScript,
      );
      if (parts.isEmpty) {
        final fb = _splitScript(_defaultScript());
        _scriptQueue.addAll(fb);
      } else {
        _scriptQueue.addAll(parts);
      }
    }
    narrating = true;
    _refreshStatus();
    notifyListeners();
    if (busy) return;
    unawaited(_runSpeakLoop());
  }

  Future<void> _enqueueQuestion(
    String question, {
    String? askId,
    String? preparedAnswer,
    String? roomIdOverride,
  }) async {
    final q = question.trim();
    if (q.isEmpty) return;
    _questionQueue.add(
      _PendingQuestion(
        q,
        askId: askId,
        preparedAnswer: preparedAnswer,
        roomIdOverride: roomIdOverride,
      ),
    );
    if (aiSpeaking && !userListening) {
      await engine.interrupt();
      await voice.stopSpeaking();
    }
    _ensureSpeakLoop();
    notifyListeners();
  }

  void _ensureSpeakLoop() {
    if (busy) return;
    if (_questionQueue.isNotEmpty) {
      unawaited(_runSpeakLoop());
      return;
    }
    if (roomLive) {
      _resumeProductNarration();
      return;
    }
    if (!narrating && _scriptQueue.isEmpty) return;
    unawaited(_runSpeakLoop());
  }

  Future<void> _runSpeakLoop() async {
    if (busy) return;
    busy = true;
    notifyListeners();
    try {
      while (roomLive ||
          narrating ||
          userListening ||
          _questionQueue.isNotEmpty ||
          _scriptQueue.isNotEmpty) {
        if (roomId.isEmpty || (!roomLive && !narrating && _questionQueue.isEmpty)) {
          _scriptQueue.clear();
          break;
        }

        // 用户正在说话：只暂停商品词，答完后继续
        if (userListening) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          continue;
        }

        // 优先回应用户消息，回完立刻回到商品讲解
        if (_questionQueue.isNotEmpty) {
          final q = _questionQueue.removeAt(0);
          final answer = q.preparedAnswer ?? await _buildAnswer(q.text);
          if (q.askId != null) {
            await sync.markAnswered(
              id: q.askId!,
              answer: answer,
              roomIdOverride: q.roomIdOverride,
            );
          }
          await _announce(answer, interrupt: true);
          if (roomLive) {
            loopNarration = true;
            narrating = true;
            if (_scriptQueue.isEmpty) {
              final parts = _splitScript(
                hostScript.trim().isEmpty ? _defaultScript() : hostScript,
              );
              _scriptQueue.addAll(parts);
            }
          }
          continue;
        }

        if (narrating && _scriptQueue.isNotEmpty) {
          final line = _scriptQueue.removeAt(0);
          final spoken = VoiceService.humanizeForSpeech(line);
          final cached = (_aheadClip != null && _aheadSpoken == spoken)
              ? _aheadClip
              : null;
          _aheadClip = null;
          _aheadSpoken = null;
          // 第一句打断清场，后面接播不掐声
          final hardStart = _scriptNeedsHardStart;
          _scriptNeedsHardStart = false;
          Future<PreparedTcp?>? warming;
          if (_scriptQueue.isNotEmpty &&
              _questionQueue.isEmpty &&
              !userListening) {
            final nextSpoken = VoiceService.humanizeForSpeech(_scriptQueue.first);
            _aheadSpoken = nextSpoken;
            warming = engine.prepareTcp(nextSpoken, rate: '-18%');
          }
          await _announce(
            line,
            interrupt: hardStart,
            showInChat: false,
            prepared: cached,
            spokenOverride: spoken,
          );
          if (warming != null) {
            final next = await warming;
            if (next != null &&
                next.gen == engine.audioGen &&
                _aheadSpoken != null &&
                _questionQueue.isEmpty &&
                !userListening) {
              _aheadClip = next;
            } else {
              _aheadClip = null;
              _aheadSpoken = null;
            }
          }
          continue;
        }

        if (narrating && _scriptQueue.isEmpty && _questionQueue.isEmpty) {
          if (loopNarration && scriptVariants.isNotEmpty) {
            _scriptVariantIndex =
                (_scriptVariantIndex + 1) % scriptVariants.length;
            hostScript = scriptVariants[_scriptVariantIndex];
            final parts = _splitScript(hostScript);
            if (parts.isNotEmpty) {
              _scriptQueue.addAll(parts);
              continue;
            }
          }
          // 直播中永不自动停讲：只有 stopNarration / stopRoom 才停
          if (roomLive && loopNarration) {
            final fallback = _splitScript(
              hostScript.trim().isEmpty ? _defaultScript() : hostScript,
            );
            if (fallback.isNotEmpty) {
              _scriptQueue.addAll(fallback);
              continue;
            }
            await Future<void>.delayed(const Duration(milliseconds: 400));
            continue;
          }
          narrating = false;
          _refreshStatus();
          notifyListeners();
          break;
        }

        if (!narrating && _questionQueue.isEmpty && !userListening) {
          if (roomLive && loopNarration) {
            narrating = true;
            continue;
          }
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    } finally {
      busy = false;
      _refreshStatus();
      notifyListeners();
      if (_questionQueue.isNotEmpty) {
        unawaited(_runSpeakLoop());
      } else if (roomLive && loopNarration) {
        _resumeProductNarration();
      } else if (narrating && _scriptQueue.isNotEmpty) {
        unawaited(_runSpeakLoop());
      }
    }
  }

  Future<String> _buildAnswer(String question) async {
    final ctx = productContext.trim().isEmpty
        ? '喜乐鲜味礼盒，直播间九十九元，食材扎实、家常鲜香，价格和规格以商品页为准。'
        : productContext.trim();
    final remote = await sync.replyQuestion(question, productContext: ctx);
    if (remote != null && remote.trim().isNotEmpty) return remote.trim();

    // 已接通大模型时：始终按当前问题生成，不走预设话术抢答
    if (llm.isLiveLlm) {
      try {
        return await llm.replyDanmaku(
          question: question,
          productContext: ctx,
        );
      } catch (_) {
        return '网络有点波动，你再说一次我马上答。';
      }
    }

    // 演示模式：先匹配预设，再本地分类型模板
    final entries = presetReplies.entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length));
    for (final entry in entries) {
      final key = entry.key.trim();
      if (key.length >= 2 && question.contains(key)) {
        return entry.value;
      }
    }
    try {
      return await llm.replyDanmaku(
        question: question,
        productContext: productContext,
      );
    } catch (_) {
      return '暂时答不上这条，换个问法试试。';
    }
  }

  Future<void> _announce(
    String text, {
    required bool interrupt,
    bool showInChat = true,
    PreparedTcp? prepared,
    String? spokenOverride,
  }) async {
    if (!roomLive && !narrating) return;
    if (showInChat) {
      messages.insert(
        0,
        LiveChatMessage(
          id: 'ai-${DateTime.now().millisecondsSinceEpoch}',
          role: ChatRole.ai,
          text: text,
          inputType: ChatInputType.voice,
        ),
      );
    }
    aiSpeaking = true;
    motion = AvatarMotion.speaking;
    notifyListeners();

    final spoken = spokenOverride ?? VoiceService.humanizeForSpeech(text);
    // 仅 App 端肢体动画；禁止引擎 set_audiotype（会静音打断 TTS）
    motion = _motionForScript(spoken);
    notifyListeners();
    var driven = false;
    // user_upload_host 走引擎 EdgeTTS(speak_tcp)：音频已通过 webview 播，
    // 即使 playPreparedTcp 因 audioStarted 回调晚到返回 false，声音也已经在响，
    // 绝不能再 fallback 到 Qwen TTS，否则两路同响。
    final useTcpVoice = engine.config.enabled &&
        !engine.config.isBaidu &&
        (engine.config.avatarId == 'user_upload_host' ||
            engine.config.hostPresenceId == 'host_upload');
    if (engine.config.enabled) {
      if (prepared != null) {
        driven = await engine.playPreparedTcp(prepared, interrupt: interrupt);
      }
      if (!driven) {
        driven = await _speakSynced(spoken, interrupt: interrupt);
      }
      if (!driven) {
        driven = await engine.speak(spoken, interrupt: interrupt, type: 'echo');
      }
      if (!driven) error = engine.lastError;
    }

    // 只有非 TCP 语音路径(百度/系统演示)才允许 fallback 到 Qwen 云 TTS
    if (!driven && !useTcpVoice) {
      try {
        await voice.speak(spoken);
      } catch (_) {}
    } else {
      final durMs = engine.speakUntil == null
          ? (spoken.length * 320 + 2000)
          : engine.speakUntil!.difference(DateTime.now()).inMilliseconds + 2500;
      var ended = false;
      final wait = engine.waitAudioEnd(
        Duration(milliseconds: durMs.clamp(4000, 120000)),
      );
      wait.whenComplete(() => ended = true);
      while (!ended) {
        if (!roomLive && !narrating) break;
        if (!interrupt && (userListening || _questionQueue.isNotEmpty)) {
          await engine.interrupt();
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }

    aiSpeaking = false;
    motion = AvatarMotion.idle;
    _refreshStatus();
    notifyListeners();
    if (isAdmin && showInChat) unawaited(_publishRoom());
  }

  AvatarMotion _motionForScript(String spoken) {
    // 真人感：偶发点头/轻挥，多数时间自然说话晃动，避免机械手势连打
    final t = spoken;
    if (RegExp(r'^家人们好|^大家好|^直播间已开启').hasMatch(t)) {
      return AvatarMotion.wave;
    }
    if (RegExp(r'扣1|链接|下单|库存|价格|多少钱').hasMatch(t)) {
      return AvatarMotion.nod;
    }
    return AvatarMotion.speaking;
  }

  Future<void> playHostGesture(AvatarMotion m) async {
    motion = m;
    notifyListeners();
    // 引擎 customvideo 与 TTS 互斥，直播口播期间只做本地动作反馈
  }

  Future<void> _gestureForScript(String spoken) async {
    motion = _motionForScript(spoken);
    notifyListeners();
  }

  void applyHostPack({
    required String product,
    required String price,
    required String sellingPoints,
    required String hostName,
    required List<DanmakuReply> replies,
  }) {
    avatarName = hostName;
    productContext =
        '$product，售价$price，卖点：$sellingPoints。预设回复：${replies.map((e) => '${e.question}=${e.answer}').join(' | ')}';
    presetReplies
      ..clear()
      ..addAll({for (final r in replies) r.question: r.answer});
    hostScript = '''
家人们好，我是AI数字人$hostName。
今天主推$product，只要$price。
$sellingPoints
适合想省事又要效果的朋友，具体以商品页为准哦。
怎么买扣1，有运费险吗也可以问我。
''';
    unawaited(_syncHostVoice().then((_) => notifyListeners()));
  }

  void bumpLikes([int? delta]) {
    final d = (delta == null || delta < 1) ? 1 : delta;
    likeCount += d;
    notifyListeners();
    unawaited(() async {
      final n = await sync.bumpLikes(delta: d, id: roomId);
      if (n != null) {
        likeCount = n;
        notifyListeners();
      }
    }());
  }
}

class _PendingQuestion {
  _PendingQuestion(
    this.text, {
    this.askId,
    this.preparedAnswer,
    this.roomIdOverride,
  });
  final String text;
  final String? askId;
  final String? preparedAnswer;
  final String? roomIdOverride;
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../models/live_chat_message.dart';
import '../models/host_presence_profile.dart';
import '../services/live_room_controller.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/digital_human_stage.dart';
import '../widgets/engine_preview_pane.dart';

/// 抖音风直播间。手机客户端只看播+提问；电脑后台才有控台按钮。
class LiveRoomScreen extends StatefulWidget {
  const LiveRoomScreen({super.key, this.adminControls, this.onExitRoom});

  /// null 时按 AppRole 自动判断
  final bool? adminControls;
  final Future<void> Function()? onExitRoom;

  @override
  State<LiveRoomScreen> createState() => _LiveRoomScreenState();
}

class _LiveRoomScreenState extends State<LiveRoomScreen> {
  final _textCtrl = TextEditingController();
  final _scriptCtrl = TextEditingController();
  final _previewKey = GlobalKey<EnginePreviewPaneState>();
  bool _hooked = false;
  bool _lastSpeaking = false;
  final List<_LikeBurst> _bursts = [];


  @override
  void dispose() {
    _textCtrl.dispose();
    _scriptCtrl.dispose();
    super.dispose();
  }

  void _hookRoom(LiveRoomController room, AppState app) {
    if (_hooked) return;
    _hooked = true;
    if (_scriptCtrl.text.isEmpty) {
      _scriptCtrl.text = room.hostScript;
    }
    room.onAvatarReady = () async {
      await _previewKey.currentState?.reconnect();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(room.isClient ? '画面已与后台同步' : '数字人形象已切换，请稍候画面刷新'),
        ),
      );
    };
    room.onPreviewMute = (muted) async {
      await _previewKey.currentState?.setMuted(muted);
    };
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final room = context.watch<LiveRoomController>();
    final real = app.dhEngine.config.enabled;
    final showAdmin = widget.adminControls ?? room.isAdmin;
    _hookRoom(room, app);
    if (room.aiSpeaking != _lastSpeaking) {
      _lastSpeaking = room.aiSpeaking;
      unawaited(_previewKey.currentState?.setActive(room.aiSpeaking));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onDoubleTapDown: (details) {
          _spawnLikeBurst(details.localPosition, room);
        },
        onTap: () {
          // 手机浏览器策略：首次点击解锁声音
          unawaited(_previewKey.currentState?.setMuted(false));
        },
        child: Stack(
        fit: StackFit.expand,
        children: [
          if (real)
            EnginePreviewPane(
              key: _previewKey,
              engine: app.dhEngine,
              roomId: room.roomId,
              onSession: room.onEngineSession,
              onError: room.onEngineError,
              onReady: () {},
              onLike: (pos) => _spawnLikeBurst(pos, room),
            )
          else
            DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF1A1A1A), Color(0xFF0B1412)],
                ),
              ),
              child: Center(
                child: room.creatingAvatar
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(color: AppColors.accent),
                          const SizedBox(height: 16),
                          Text(
                            room.createHint.isEmpty
                                ? '正在生成数字人 ${room.avatarProgress}%'
                                : room.createHint,
                            style: const TextStyle(color: Colors.white),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      )
                    : DigitalHumanStage(
                        motion: room.motion,
                        isSpeaking: room.aiSpeaking,
                        avatarPath: room.avatarPath,
                        name: room.avatarName,
                        pose: (HostPresenceProfile.byId(
                                    app.dhEngine.config.hostPresenceId) ??
                                HostPresenceProfile.byAvatarId(
                                    app.dhEngine.config.avatarId))
                            ?.pose ??
                            HostPose.stand,
                      ),
              ),
            ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onLongPress: showAdmin
                        ? () {
                            // 长按标题：提示可在大厅重选房间（由上层 AdminRoot 处理）
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('请返回大厅切换直播间：关闭本页后重开后台，或重启应用选房'),
                              ),
                            );
                          }
                        : () => _clientEngineDialog(context, app),
                    child: showAdmin
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 14,
                                  backgroundColor: AppColors.brand,
                                  backgroundImage: room.avatarPath != null
                                      ? FileImage(File(room.avatarPath!))
                                      : null,
                                  child: room.avatarPath == null
                                      ? Text(
                                          room.avatarName.isNotEmpty
                                              ? room.avatarName.substring(0, 1)
                                              : '乐',
                                          style: const TextStyle(fontSize: 12, color: Colors.white),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(room.roomTitle,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        )),
                                    Text(
                                      '${room.viewerCount} 观看 · ${_formatLikes(room.likeCount)}赞',
                                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          )
                        : Text(
                            room.roomTitle,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              shadows: [
                                Shadow(blurRadius: 8, color: Colors.black87),
                              ],
                            ),
                          ),
                  ),
                  const Spacer(),
                  if (showAdmin) ...[
                    _Pill(
                      color: room.roomLive ? const Color(0xFFFF2D55) : Colors.white24,
                      text: room.roomLive ? 'LIVE' : '未开播',
                    ),
                    const SizedBox(width: 6),
                    _Pill(
                      color: room.isRealEngine ? AppColors.brand : const Color(0xFF4A6670),
                      text: room.isRealEngine ? '后台预览' : (real ? '连接中' : '演示'),
                    ),
                  ] else if (room.roomLive)
                    const _Pill(
                      color: Color(0xFFFF2D55),
                      text: 'LIVE',
                    ),
                ],
              ),
            ),
          ),

          // 退出 X：固定右上角
          if (widget.onExitRoom != null)
            Positioned(
              right: 12,
              top: MediaQuery.paddingOf(context).top + 8,
              child: Material(
                color: Colors.black.withValues(alpha: 0.55),
                shape: const CircleBorder(),
                elevation: 2,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => widget.onExitRoom?.call(),
                  child: const SizedBox(
                    width: 40,
                    height: 40,
                    child: Icon(Icons.close, color: Colors.white, size: 22),
                  ),
                ),
              ),
            ),

          Positioned(
            left: 12,
            top: MediaQuery.paddingOf(context).top + (showAdmin ? 64 : 48),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'AI数字人 · 人工智能生成',
                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
          ),

          // 双击点赞：一串小心心往上飘
          ..._bursts.map((b) => Positioned(
                left: b.pos.dx - 16,
                top: b.pos.dy - 16,
                child: IgnorePointer(
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey(b.id),
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 900),
                    builder: (context, t, child) {
                      return Opacity(
                        opacity: (1 - t).clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(b.drift * t, -180 * t),
                          child: Transform.scale(
                            scale: 0.7 + 0.5 * (1 - t),
                            child: child,
                          ),
                        ),
                      );
                    },
                    child: const Icon(Icons.favorite, color: Color(0xFFFF2D55), size: 28),
                  ),
                ),
              )),

          // 右侧：仅后台显示控台；客户端只保留点赞
          Positioned(
            right: 10,
            bottom: 168,
            child: Column(
              children: [
                if (showAdmin) ...[
                  _SideBtn(
                    icon: Icons.add_a_photo_outlined,
                    label: '做数字人',
                    onTap: () => _photoSheet(context, room),
                  ),
                  const SizedBox(height: 12),
                  _SideBtn(
                    icon: room.narrating ? Icons.pause_circle_outline : Icons.record_voice_over,
                    label: room.narrating ? '停讲解' : '讲话术',
                    onTap: () {
                      if (room.narrating) {
                        room.stopNarration();
                      } else {
                        room.setHostScript(_scriptCtrl.text);
                        room.startNarration();
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  _SideBtn(
                    icon: Icons.article_outlined,
                    label: '话术',
                    onTap: () => _editScript(context, room),
                  ),
                  const SizedBox(height: 12),
                ],
                _SideBtn(
                  icon: Icons.favorite,
                  label: _formatLikes(room.likeCount),
                  onTap: room.bumpLikes,
                  iconColor: const Color(0xFFFF2D55),
                ),
                if (showAdmin) ...[
                  const SizedBox(height: 12),
                  _SideBtn(
                    icon: room.roomLive ? Icons.stop_circle : Icons.podcasts,
                    label: room.roomLive ? '停播' : '开播',
                    onTap: () {
                      if (room.roomLive) {
                        room.stopRoom();
                      } else {
                        room.startRoom();
                      }
                    },
                  ),
                ],
              ],
            ),
          ),

          Positioned(
            left: 0,
            right: 72,
            bottom: 88,
            height: MediaQuery.sizeOf(context).height * (showAdmin ? 0.28 : 0.18),
            child: _DanmakuList(
              messages: room.messages,
              maxItems: showAdmin ? 12 : 3,
            ),
          ),

          if (room.userListening || room.creatingAvatar || (showAdmin && room.narrating))
            Positioned(
              left: 16,
              right: 80,
              bottom: 100,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  room.creatingAvatar
                      ? room.createHint
                      : room.userListening
                          ? '🎤 ${room.listenHint.isEmpty ? '松手发送 · 上滑取消' : room.listenHint}'
                          : '📢 正在讲解话术，观众提问会优先回答',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(10, 8, 10, 8 + MediaQuery.paddingOf(context).bottom),
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (room.error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(room.error!,
                          style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 11)),
                    ),
                  // 观众端不展示引擎/模型技术状态行
                  if (showAdmin) ...[
                    Text(room.statusLine,
                        style: const TextStyle(color: Colors.white54, fontSize: 11)),
                    const SizedBox(height: 6),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _textCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: showAdmin ? '模拟观众提问…' : '说点什么或发语音提问…',
                            hintStyle: const TextStyle(color: Colors.white38),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.12),
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onSubmitted: (_) async {
                            final t = _textCtrl.text;
                            _textCtrl.clear();
                            await room.sendText(t);
                          },
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton.filled(
                        onPressed: () async {
                          final t = _textCtrl.text;
                          _textCtrl.clear();
                          await room.sendText(t);
                        },
                        icon: const Icon(Icons.send),
                      ),
                      Listener(
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: (_) => _onVoicePointerDown(room),
                        onPointerMove: (e) => _onVoicePointerMove(e, room),
                        onPointerUp: (_) => _onVoicePointerUp(room),
                        onPointerCancel: (_) => _onVoicePointerCancel(room),
                        child: Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: room.userListening
                                ? (room.voiceCancelArmed
                                    ? const Color(0xFF8E8E93)
                                    : const Color(0xFFFF2D55))
                                : AppColors.brandSoft,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            room.userListening ? Icons.mic : Icons.mic_none,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }

  void _spawnLikeBurst(Offset localPos, LiveRoomController room) {
    unawaited(_previewKey.currentState?.setMuted(false));
    room.bumpLikes(1);
    final id = DateTime.now().microsecondsSinceEpoch;
    setState(() {
      _bursts.add(_LikeBurst(id: id, pos: localPos, drift: 0));
    });
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() => _bursts.removeWhere((e) => e.id == id));
    });
  }

  double? _voiceDownY;
  bool _voiceHoldBusy = false;
  Future<void>? _voiceBeginFuture;

  Future<void> _onVoicePointerDown(LiveRoomController room) async {
    if (_voiceHoldBusy || room.userListening) return;
    _voiceHoldBusy = true;
    _voiceDownY = null;
    final begin = () async {
      try {
        final status = await Permission.microphone.request();
        if (!status.isGranted) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('需要麦克风权限才能语音提问')),
          );
          return;
        }
        unawaited(_previewKey.currentState?.setMuted(true));
        await room.beginVoiceHold();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '语音失败：${e.toString().replaceFirst('Exception: ', '')}',
            ),
          ),
        );
        unawaited(_previewKey.currentState?.setMuted(false));
      } finally {
        _voiceHoldBusy = false;
      }
    }();
    _voiceBeginFuture = begin;
    await begin;
  }

  void _onVoicePointerMove(PointerMoveEvent e, LiveRoomController room) {
    if (!room.userListening) return;
    _voiceDownY ??= e.position.dy;
    final dy = (_voiceDownY! - e.position.dy);
    // 上滑超过 60px → 取消（微信同款）
    room.setVoiceCancelArmed(dy > 60);
  }

  Future<void> _onVoicePointerUp(LiveRoomController room) async {
    try {
      if (_voiceBeginFuture != null) await _voiceBeginFuture;
      if (!room.userListening) return;
      await room.endVoiceHold();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '语音失败：${e.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    } finally {
      unawaited(_previewKey.currentState?.setMuted(false));
      _voiceDownY = null;
      _voiceBeginFuture = null;
    }
  }

  Future<void> _onVoicePointerCancel(LiveRoomController room) async {
    try {
      if (_voiceBeginFuture != null) await _voiceBeginFuture;
      if (!room.userListening) return;
      await room.cancelVoiceHold();
    } finally {
      unawaited(_previewKey.currentState?.setMuted(false));
      _voiceDownY = null;
      _voiceBeginFuture = null;
    }
  }

  Future<void> _clientEngineDialog(BuildContext context, AppState app) async {
    final ctrl = TextEditingController(text: app.dhEngine.config.engineBaseUrl);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('连接直播引擎'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: '电脑引擎地址',
            hintText: 'http://192.168.x.x:8010',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('连接')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      final cfg = app.dhEngine.config;
      cfg.engineBaseUrl = ctrl.text.trim();
      cfg.enabled = true;
      app.saveDigitalHumanConfig(cfg);
      await _previewKey.currentState?.reconnect();
    }
    ctrl.dispose();
  }

  String _formatLikes(int n) {
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    return '$n';
  }

  void _photoSheet(BuildContext context, LiveRoomController room) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('用照片生成 AI 数字人',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text(
                '请上传清晰正面人像。相机会传到电脑 GPU 引擎：照片→短视频→数字人形象，然后用于直播讲解与答问。',
                style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  room.createDigitalHumanFromPhoto(fromCamera: false);
                },
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('从相册选择人物照片'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  room.createDigitalHumanFromPhoto(fromCamera: true);
                },
                icon: const Icon(Icons.photo_camera_outlined, color: Colors.white),
                label: const Text('拍照生成', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _editScript(BuildContext context, LiveRoomController room) {
    _scriptCtrl.text = room.hostScript;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.viewInsetsOf(ctx).bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('直播讲解话术',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              TextField(
                controller: _scriptCtrl,
                maxLines: 8,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: '输入要讲解的口播内容…',
                  hintStyle: TextStyle(color: Colors.white38),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  room.setHostScript(_scriptCtrl.text);
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('话术已保存，点「讲话术」开始边讲边答')),
                  );
                },
                child: const Text('保存话术'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.color, required this.text});
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
      child: Text(text,
          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
    );
  }
}

class _SideBtn extends StatelessWidget {
  const _SideBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor = Colors.white,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
        ],
      ),
    );
  }
}

class _DanmakuList extends StatelessWidget {
  const _DanmakuList({required this.messages, this.maxItems = 12});
  final List<LiveChatMessage> messages;
  final int maxItems;

  @override
  Widget build(BuildContext context) {
    final visible = messages
        .where((m) => m.isUser || m.isAi)
        .take(maxItems)
        .toList();
    // 公屏：仅观众提问与针对提问的回答（讲解话术不进列表）
    if (visible.isEmpty) {
      return const SizedBox.shrink();
    }
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      itemCount: visible.length,
      itemBuilder: (context, i) {
        final m = visible[i];
        final name = m.isUser
            ? (m.inputType == ChatInputType.voice ? '观众·语音' : '观众')
            : '数字人';
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '$name ',
                    style: TextStyle(
                      color: m.isAi ? AppColors.accent : const Color(0xFF7FDBFF),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  TextSpan(
                    text: m.text,
                    style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.3),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LikeBurst {
  _LikeBurst({required this.id, required this.pos, this.drift = 0});
  final int id;
  final Offset pos;
  final double drift;
}

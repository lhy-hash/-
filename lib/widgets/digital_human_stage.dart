import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/host_presence_profile.dart';
import '../services/live_room_controller.dart';
import '../theme/app_theme.dart';

/// 全身出镜直播感舞台：竖屏站姿/坐姿主播
class DigitalHumanStage extends StatefulWidget {
  const DigitalHumanStage({
    super.key,
    required this.motion,
    required this.isSpeaking,
    this.avatarPath,
    this.name = '小乐',
    this.pose = HostPose.stand,
  });

  final AvatarMotion motion;
  final bool isSpeaking;
  final String? avatarPath;
  final String name;
  final HostPose pose;

  @override
  State<DigitalHumanStage> createState() => _DigitalHumanStageState();
}

class _DigitalHumanStageState extends State<DigitalHumanStage>
    with TickerProviderStateMixin {
  late final AnimationController _breath;
  late final AnimationController _talk;
  late final AnimationController _gesture;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat(reverse: true);
    _talk = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    _gesture = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _syncTalk();
  }

  @override
  void didUpdateWidget(covariant DigitalHumanStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isSpeaking != widget.isSpeaking ||
        oldWidget.motion != widget.motion) {
      _syncTalk();
    }
  }

  void _syncTalk() {
    if (widget.isSpeaking || widget.motion == AvatarMotion.speaking) {
      if (!_talk.isAnimating) _talk.repeat(reverse: true);
    } else {
      _talk
        ..stop()
        ..value = 0;
    }
    if (widget.motion == AvatarMotion.wave ||
        widget.motion == AvatarMotion.nod ||
        widget.motion == AvatarMotion.point) {
      _gesture.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    _talk.dispose();
    _gesture.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_breath, _talk, _gesture]),
      builder: (context, _) {
        final breath = math.sin(_breath.value * math.pi);
        // 真人感：持续小幅呼吸/晃肩，说话时略加强，不做夸张机械手势
        final speakBoost = widget.isSpeaking ? _talk.value * 0.55 : 0.0;
        final sway = breath * 2.4 + (widget.isSpeaking ? speakBoost * 1.2 : 0.0);
        var handLift = -0.03 + breath * 0.035;
        var nod = breath * 1.1;

        switch (widget.motion) {
          case AvatarMotion.wave:
            handLift = -0.18 + _gesture.value * 0.35;
            break;
          case AvatarMotion.nod:
            nod = math.sin(_gesture.value * math.pi) * 3.2;
            break;
          case AvatarMotion.point:
            handLift = 0.02 + _gesture.value * 0.12;
            break;
          case AvatarMotion.speaking:
            nod += math.sin(_talk.value * math.pi) * 0.9;
            break;
          case AvatarMotion.idle:
            break;
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            // 演播厅氛围
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF1A2420),
                    Color(0xFF0B1412),
                    Color(0xFF070C0A),
                  ],
                ),
              ),
            ),
            // 柔光
            Positioned(
              top: -80,
              left: 40,
              right: 40,
              child: Container(
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.brand.withValues(alpha: 0.28),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            // 全身/半身主播出镜
            Align(
              alignment: const Alignment(0, 0.18),
              child: Transform.translate(
                offset: Offset(sway * 0.35, breath * 2.5),
                child: Transform.rotate(
                  angle: sway * 0.004,
                  child: SizedBox(
                    width: MediaQuery.sizeOf(context).width * 0.92,
                    height: MediaQuery.sizeOf(context).height * 0.72,
                    child: _PresenterBody(
                      avatarPath: widget.avatarPath,
                      name: widget.name,
                      speaking: widget.isSpeaking,
                      mouthOpen: 2.0 + speakBoost * 12,
                      handLift: handLift,
                      nod: nod,
                      sitting: widget.pose == HostPose.sit,
                    ),
                  ),
                ),
              ),
            ),
            // 底部演播信息
            Positioned(
              left: 16,
              right: 16,
              bottom: 18,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    color: Colors.black.withValues(alpha: 0.42),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: widget.isSpeaking
                                ? const Color(0xFFFF4D6A)
                                : AppColors.brand,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.isSpeaking
                                ? '${widget.name} 正在口播讲解'
                                : '${widget.name} · 站姿出镜直播中',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Text(
                          'AI数字人',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PresenterBody extends StatelessWidget {
  const _PresenterBody({
    required this.avatarPath,
    required this.name,
    required this.speaking,
    required this.mouthOpen,
    required this.handLift,
    required this.nod,
    this.sitting = false,
  });

  final String? avatarPath;
  final String name;
  final bool speaking;
  final double mouthOpen;
  final double handLift;
  final double nod;
  final bool sitting;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = avatarPath != null && File(avatarPath!).existsSync();
    final bodyH = sitting ? 300.0 : 420.0;
    final headTop = sitting ? 48.0 : 8.0;

    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        // 身体剪影（站姿 / 坐姿）
        Positioned(
          bottom: sitting ? 24 : 0,
          child: Transform.translate(
            offset: Offset(0, -handLift * 8),
            child: CustomPaint(
              size: Size(260, bodyH),
              painter: _BodyPainter(
                femaleHint: !RegExp(r'(哥|阿杰|阿乐|先生)').hasMatch(name),
                sitting: sitting,
              ),
            ),
          ),
        ),
        // 头部：照片或首字，带轻微点头
        Positioned(
          top: headTop,
          child: Transform.translate(
            offset: Offset(0, nod),
            child: Column(
              children: [
                Container(
                  width: 168,
                  height: sitting ? 190 : 210,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 28,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (hasPhoto)
                        Image.file(
                          File(avatarPath!),
                          fit: BoxFit.cover,
                          alignment: const Alignment(0, -0.25),
                        )
                      else
                        Container(
                          color: const Color(0xFF1E6B54),
                          alignment: Alignment.center,
                          child: Text(
                            name.isNotEmpty ? name.substring(0, 1) : '乐',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 72,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      // 说话时唇部动态（轻量，不挡脸）
                      if (speaking)
                        Align(
                          alignment: const Alignment(0, 0.62),
                          child: Container(
                            width: 28 + mouthOpen * 0.35,
                            height: mouthOpen.clamp(3, 14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3A1A1A)
                                  .withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BodyPainter extends CustomPainter {
  _BodyPainter({required this.femaleHint, this.sitting = false});

  final bool femaleHint;
  final bool sitting;

  @override
  void paint(Canvas canvas, Size size) {
    final torso = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: femaleHint
            ? const [Color(0xFF2F9E7A), Color(0xFF1A4D3D)]
            : const [Color(0xFF3A5A72), Color(0xFF1A2A38)],
      ).createShader(Offset.zero & size);

    final w = size.width;
    final h = size.height;
    if (sitting) {
      // 坐姿：上半身 + 简易椅面
      final chair = Paint()..color = const Color(0xFF24302C);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.12, h * 0.62, w * 0.76, h * 0.28),
          const Radius.circular(12),
        ),
        chair,
      );
      final path = Path()
        ..moveTo(w * 0.34, h * 0.06)
        ..quadraticBezierTo(w * 0.20, h * 0.28, w * 0.22, h * 0.58)
        ..lineTo(w * 0.78, h * 0.58)
        ..quadraticBezierTo(w * 0.80, h * 0.28, w * 0.66, h * 0.06)
        ..close();
      canvas.drawPath(path, torso);
      return;
    }
    final path = Path()
      ..moveTo(w * 0.35, h * 0.08)
      ..quadraticBezierTo(w * 0.22, h * 0.22, w * 0.18, h * 0.42)
      ..quadraticBezierTo(w * 0.14, h * 0.72, w * 0.22, h * 0.98)
      ..lineTo(w * 0.78, h * 0.98)
      ..quadraticBezierTo(w * 0.86, h * 0.72, w * 0.82, h * 0.42)
      ..quadraticBezierTo(w * 0.78, h * 0.22, w * 0.65, h * 0.08)
      ..close();
    canvas.drawPath(path, torso);
  }

  @override
  bool shouldRepaint(covariant _BodyPainter oldDelegate) =>
      oldDelegate.femaleHint != femaleHint || oldDelegate.sitting != sitting;
}

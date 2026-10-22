import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app_role.dart';
import 'models/digital_human_config.dart';
import 'screens/analytics_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/live_room_screen.dart';
import 'screens/lobby_screen.dart';
import 'screens/scripts_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/studio_screen.dart';
import 'services/auth_service.dart';
import 'services/live_room_controller.dart';
import 'services/room_sync_service.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

/// 真机优先 USB 转发 127.0.0.1；同一局域网再用电脑当前地址
const String kPhoneEngineUrl = String.fromEnvironment(
  'XILE_ENGINE_URL',
  defaultValue: 'http://127.0.0.1:8010',
);

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  final role = resolveAppRole(args: args);
  setRuntimeRole(role);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(XileApp(role: role));
}

class XileApp extends StatelessWidget {
  const XileApp({super.key, required this.role});

  final AppRole role;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()..init()),
        ChangeNotifierProvider(
          create: (context) {
            final app = context.read<AppState>();
            if (role == AppRole.client) {
              app.dhEngine.config.enabled = true;
              app.dhEngine.config.provider = DhProvider.local;
              final onPhone = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
              app.dhEngine.config.engineBaseUrl =
                  onPhone ? kPhoneEngineUrl : 'http://127.0.0.1:8010';
            }
            return LiveRoomController(
              llm: app.llm,
              engine: app.dhEngine,
              role: role,
            )..init();
          },
        ),
      ],
      child: MaterialApp(
        title: role == AppRole.admin ? '喜乐管理后台' : '喜乐观众端',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        home: role == AppRole.client
            ? const ClientRootPage()
            : const AdminRootPage(),
      ),
    );
  }
}

class ClientRootPage extends StatefulWidget {
  const ClientRootPage({super.key});

  @override
  State<ClientRootPage> createState() => _ClientRootPageState();
}

class _ClientRootPageState extends State<ClientRootPage> {
  late final AuthService _auth;
  late final RoomSyncService _sync;
  bool _ready = false;
  bool _inRoom = false;

  @override
  void initState() {
    super.initState();
    final room = context.read<LiveRoomController>();
    final base = room.engine.config.normalizedBase;
    _auth = AuthService(baseUrl: base);
    _sync = RoomSyncService(baseUrl: base);
    _boot();
  }

  Future<void> _boot() async {
    final room = context.read<LiveRoomController>();
    _auth.baseUrl = room.engine.config.normalizedBase;
    _sync.baseUrl = room.engine.config.normalizedBase;
    final reached = await _sync.resolveReachableBase();
    if (reached != null) {
      room.engine.config.engineBaseUrl = reached;
      _auth.baseUrl = reached;
    }
    await _auth.loadSaved();
    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        backgroundColor: Color(0xFF0B1412),
        body: Center(child: CircularProgressIndicator(color: AppColors.accent)),
      );
    }
    if (_auth.current == null) {
      return AuthScreen(
        auth: _auth,
        onSuccess: () => setState(() {}),
      );
    }
    if (!_inRoom) {
      return LobbyScreen(
        sync: _sync,
        auth: _auth,
        onLogout: () async {
          await context.read<LiveRoomController>().leaveRoom();
          await _auth.logout();
          if (mounted) setState(() => _inRoom = false);
        },
        onSwitchAccount: () async {
          await context.read<LiveRoomController>().leaveRoom();
          await _auth.logout();
          if (mounted) setState(() => _inRoom = false);
        },
        onEnterRoom: (r) async {
          final room = context.read<LiveRoomController>();
          await room.enterRoom(r);
          setState(() => _inRoom = true);
        },
      );
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await _confirmLeaveRoom();
        if (ok != true || !mounted) return;
        await context.read<LiveRoomController>().leaveRoom();
        setState(() => _inRoom = false);
      },
      child: LiveRoomScreen(
        adminControls: false,
        onExitRoom: () async {
          final ok = await _confirmLeaveRoom();
          if (ok != true || !mounted) return;
          await context.read<LiveRoomController>().leaveRoom();
          setState(() => _inRoom = false);
        },
      ),
    );
  }

  Future<bool?> _confirmLeaveRoom() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2A28),
        title: const Text('退出直播间', style: TextStyle(color: Colors.white)),
        content: const Text(
          '确定退出吗？退出后将立即停止数字人讲解与声音。',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
  }
}

class AdminRootPage extends StatefulWidget {
  const AdminRootPage({super.key});

  @override
  State<AdminRootPage> createState() => _AdminRootPageState();
}

class _AdminRootPageState extends State<AdminRootPage> {
  bool _picked = false;

  @override
  Widget build(BuildContext context) {
    final room = context.watch<LiveRoomController>();
    final sync = RoomSyncService(baseUrl: room.engine.config.normalizedBase);
    final auth = AuthService(baseUrl: room.engine.config.normalizedBase)
      ..current = const AuthUser(
        token: 'admin',
        username: 'admin',
        displayName: '管理员',
      );

    if (!_picked) {
      return LobbyScreen(
        sync: sync,
        auth: auth,
        adminMode: true,
        onEnterRoom: (r) async {
          await room.enterRoom(r);
          setState(() => _picked = true);
        },
      );
    }
    return AdminShellPage(
      onSwitchRoom: () async {
        await room.leaveRoom();
        if (mounted) setState(() => _picked = false);
      },
    );
  }
}

class AdminShellPage extends StatelessWidget {
  const AdminShellPage({super.key, this.onSwitchRoom});

  final Future<void> Function()? onSwitchRoom;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final pages = [
      LiveRoomScreen(adminControls: true, onExitRoom: onSwitchRoom),
      const StudioScreen(),
      const ScriptsScreen(),
      const AnalyticsScreen(),
      const SettingsScreen(),
    ];
    final index = state.tabIndex.clamp(0, pages.length - 1);

    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        child: KeyedSubtree(
          key: ValueKey(index),
          child: pages[index],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: state.setTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.live_tv_outlined),
            selectedIcon: Icon(Icons.live_tv),
            label: '控台',
          ),
          NavigationDestination(
            icon: Icon(Icons.handyman_outlined),
            selectedIcon: Icon(Icons.handyman),
            label: '工坊',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book_rounded),
            label: '脚本',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: '数据',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}

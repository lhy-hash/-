import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/room_sync_service.dart';
import '../theme/app_theme.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({
    super.key,
    required this.sync,
    required this.auth,
    required this.onEnterRoom,
    this.onLogout,
    this.onSwitchAccount,
    this.adminMode = false,
  });

  final RoomSyncService sync;
  final AuthService auth;
  final void Function(SyncRoomState room) onEnterRoom;
  final VoidCallback? onLogout;
  final VoidCallback? onSwitchAccount;
  final bool adminMode;

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  List<SyncRoomState> _rooms = const [];
  bool _loading = true;
  String? _error;

  String _dhCoverUrl(SyncRoomState room) {
    final base = widget.sync.baseUrl.replaceAll(RegExp(r'/$'), '');
    // 封面强制跟房间 avatarId，与进房数字人同一套真人形象
    final avatar = room.avatarId.isNotEmpty
        ? room.avatarId
        : 'wav2lip_avatar_female_model';
    return '$base/api/xile/cover?avatar=${Uri.encodeComponent(avatar)}&v=${room.revision}';
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    // 先自动探测可达的引擎地址（覆盖手机里存的旧地址）
    await widget.sync.resolveReachableBase();
    final rooms = await widget.sync.listRooms();
    if (!mounted) return;
    setState(() {
      _rooms = rooms;
      _loading = false;
      if (rooms.isEmpty) {
        _error = '暂无直播间，请确认电脑引擎已启动（8010）且手机和电脑在同一网络';
      }
    });
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2A28),
        title: const Text('退出登录', style: TextStyle(color: Colors.white)),
        content: const Text(
          '确定退出当前账号吗？退出后需要重新登录才能进入直播间。',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF2D55)),
            child: const Text('退出登录'),
          ),
        ],
      ),
    );
    if (ok == true) widget.onLogout?.call();
  }

  Future<void> _confirmSwitch() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2A28),
        title: const Text('切换账号', style: TextStyle(color: Colors.white)),
        content: const Text(
          '确定切换登录账号吗？将退出当前账号并返回登录页。',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('切换登录'),
          ),
        ],
      ),
    );
    if (ok == true) (widget.onSwitchAccount ?? widget.onLogout)?.call();
  }

  String? _coverNetwork(SyncRoomState room) => _dhCoverUrl(room);

  @override
  Widget build(BuildContext context) {
    final name = widget.auth.current?.displayName ?? '嘉宾';
    return Scaffold(
      backgroundColor: const Color(0xFF0B1412),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(widget.adminMode ? '选择要控台的直播间' : '喜乐直播大厅'),
        actions: [
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
          if (!widget.adminMode && widget.onSwitchAccount != null)
            TextButton(
              onPressed: _confirmSwitch,
              child: const Text('切换登录', style: TextStyle(color: Colors.white70)),
            ),
          if (widget.onLogout != null)
            IconButton(
              onPressed: _confirmLogout,
              tooltip: '退出登录',
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : RefreshIndicator(
              onRefresh: _reload,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '你好，$name',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.adminMode
                                ? '进入后可开播讲解、换形象、同步手机端'
                                : '选择数字人直播间，封面即主播形象',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.55),
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              style: const TextStyle(color: Color(0xFFFF8A80)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.72,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => _roomCard(_rooms[i]),
                        childCount: _rooms.length,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _roomCard(SyncRoomState room) {
    final live = room.live;
    final net = _coverNetwork(room);
    return Material(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => widget.onEnterRoom(room),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 真人数字人照片封面（与直播间同一形象）
                  if (net != null)
                    Image.network(
                      net,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => _coverFallback(room, live),
                    )
                  else
                    _coverFallback(room, live),
                  // 底部渐变，突出真人主播感
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 48,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.55),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    top: 8,
                    child: live
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF2D55),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              '直播中',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    room.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${room.hostName} · ${room.productName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.accent, fontSize: 11),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${room.viewerCount}观看 · ${_fmt(room.likeCount)}赞',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _coverFallback(SyncRoomState room, bool live) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: live
              ? const [Color(0xFF2A8F7A), Color(0xFF163A34)]
              : const [Color(0xFF444444), Color(0xFF222222)],
        ),
      ),
      child: Center(
        child: Text(
          room.hostName,
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
      ),
    );
  }

  String _fmt(int n) {
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    return '$n';
  }
}

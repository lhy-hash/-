import 'dart:convert';

import 'package:http/http.dart' as http;

class SyncRoomState {
  const SyncRoomState({
    required this.id,
    required this.avatarId,
    this.voiceProfileId = '',
    this.hostPresenceId = '',
    required this.live,
    required this.title,
    required this.hostName,
    required this.coverHint,
    required this.coverUrl,
    required this.productName,
    required this.productPrice,
    required this.productContext,
    required this.hostScript,
    required this.scriptVariants,
    required this.statusLine,
    required this.revision,
    required this.clientSessionId,
    required this.adminSessionId,
    required this.previewSessionId,
    required this.messages,
    required this.pendingAskCount,
    required this.viewerCount,
    required this.likeCount,
  });

  final String id;
  final String avatarId;
  final String voiceProfileId;
  final String hostPresenceId;
  final bool live;
  final String title;
  final String hostName;
  final String coverHint;
  final String coverUrl;
  final String productName;
  final String productPrice;
  final String productContext;
  final String hostScript;
  final List<String> scriptVariants;
  final String statusLine;
  final int revision;
  final String clientSessionId;
  final String adminSessionId;
  final String previewSessionId;
  final List<SyncChatMessage> messages;
  final int pendingAskCount;
  final int viewerCount;
  final int likeCount;

  factory SyncRoomState.fromJson(Map<String, dynamic> j) {
    final raw = j['messages'];
    final msgs = <SyncChatMessage>[];
    if (raw is List) {
      for (final m in raw) {
        if (m is Map<String, dynamic>) {
          msgs.add(SyncChatMessage.fromJson(m));
        } else if (m is Map) {
          msgs.add(SyncChatMessage.fromJson(Map<String, dynamic>.from(m)));
        }
      }
    }
    return SyncRoomState(
      id: '${j['id'] ?? ''}',
      avatarId: '${j['avatarId'] ?? ''}',
      voiceProfileId: '${j['voiceProfileId'] ?? ''}',
      hostPresenceId: '${j['hostPresenceId'] ?? ''}',
      live: j['live'] == true,
      title: '${j['title'] ?? '喜乐直播间'}',
      hostName: '${j['hostName'] ?? '数字人'}',
      coverHint: '${j['coverHint'] ?? ''}',
      coverUrl: '${j['coverUrl'] ?? ''}',
      productName: '${j['productName'] ?? ''}',
      productPrice: '${j['productPrice'] ?? ''}',
      productContext: '${j['productContext'] ?? ''}',
      hostScript: '${j['hostScript'] ?? ''}',
      scriptVariants: () {
        final raw = j['scriptVariants'];
        if (raw is! List) return const <String>[];
        return raw.map((e) => '$e'.trim()).where((e) => e.isNotEmpty).toList();
      }(),
      statusLine: '${j['statusLine'] ?? ''}',
      revision: (j['revision'] as num?)?.toInt() ?? 0,
      clientSessionId: '${j['clientSessionId'] ?? ''}',
      adminSessionId: '${j['adminSessionId'] ?? ''}',
      previewSessionId: '${j['previewSessionId'] ?? ''}',
      messages: msgs,
      pendingAskCount: (j['pendingAskCount'] as num?)?.toInt() ?? 0,
      viewerCount: (j['viewerCount'] as num?)?.toInt() ?? 0,
      likeCount: (j['likeCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class SyncChatMessage {
  const SyncChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.ts,
  });

  final String id;
  final String role;
  final String text;
  final int ts;

  factory SyncChatMessage.fromJson(Map<String, dynamic> j) => SyncChatMessage(
        id: '${j['id'] ?? ''}',
        role: '${j['role'] ?? 'system'}',
        text: '${j['text'] ?? ''}',
        ts: (j['ts'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        'text': text,
        'ts': ts,
      };
}

class SyncAsk {
  const SyncAsk({
    required this.id,
    required this.text,
    required this.ts,
    required this.roomId,
  });

  final String id;
  final String text;
  final int ts;
  final String roomId;

  factory SyncAsk.fromJson(Map<String, dynamic> j) => SyncAsk(
        id: '${j['id'] ?? ''}',
        text: '${j['text'] ?? ''}',
        ts: (j['ts'] as num?)?.toInt() ?? 0,
        roomId: '${j['roomId'] ?? ''}',
      );
}

class AnswerResult {
  const AnswerResult({
    required this.clientSessionId,
    required this.previewSessionId,
    required this.adminSessionId,
    required this.roomId,
  });

  final String clientSessionId;
  final String previewSessionId;
  final String adminSessionId;
  final String roomId;
}

/// 通过 LiveTalking 上的 /api/xile/* 同步后台与手机
class RoomSyncService {
  RoomSyncService({required this.baseUrl});

  String baseUrl;
  String? roomId;

  String get _root {
    var u = baseUrl.trim();
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    return u;
  }

  Uri _uri(String path, [Map<String, String>? q]) {
    return Uri.parse('$_root$path').replace(queryParameters: q);
  }

  static const fallbackBases = <String>[
    'http://127.0.0.1:8010',
    'http://172.20.10.5:8010', // iPhone 热点网段
    'http://192.168.100.103:8010',
    'http://192.168.40.241:8010',
    'http://192.168.156.212:8010',
    'http://192.168.156.1:8010',
    'http://172.29.32.1:8010',
  ];

  /// 电脑换了网段时，按候选地址找到还能打开的引擎。
  Future<String?> resolveReachableBase() async {
    final seen = <String>{};
    final tries = <String>[baseUrl, ...fallbackBases];
    for (final raw in tries) {
      var u = raw.trim();
      if (u.endsWith('/')) u = u.substring(0, u.length - 1);
      if (u.isEmpty || !seen.add(u)) continue;
      try {
        final res = await http
            .get(Uri.parse('$u/api/xile/rooms'))
            .timeout(const Duration(seconds: 2));
        if (res.statusCode == 200) {
          baseUrl = u;
          return u;
        }
      } catch (_) {}
    }
    return null;
  }

  Future<List<SyncRoomState>> listRooms() async {
    try {
      final res = await http
          .get(_uri('/api/xile/rooms'))
          .timeout(const Duration(seconds: 6));
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (body is Map && body['code'] == 0 && body['data'] is Map) {
        final list = (body['data'] as Map)['rooms'];
        if (list is List) {
          return list
              .whereType<Map>()
              .map((e) => SyncRoomState.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
      }
    } catch (_) {}
    return const [];
  }

  Future<SyncRoomState?> fetchRoom({String? id}) async {
    final rid = id ?? roomId ?? '';
    try {
      final res = await http
          .get(_uri('/api/xile/room', {
            if (rid.isNotEmpty) 'id': rid,
          }))
          .timeout(const Duration(seconds: 5));
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (body is Map && body['code'] == 0 && body['data'] is Map) {
        return SyncRoomState.fromJson(
          Map<String, dynamic>.from(body['data'] as Map),
        );
      }
    } catch (_) {}
    return null;
  }

  Future<bool> publishRoom({
    required String avatarId,
    required bool live,
    required String title,
    required String statusLine,
    String? id,
    String? adminSessionId,
    String? clientSessionId,
    String? previewSessionId,
    String? hostName,
    String? coverHint,
    String? productName,
    String? productPrice,
    String? productContext,
    String? hostScript,
    String? voiceProfileId,
    int? likeCount,
    int? viewerCount,
    List<Map<String, dynamic>>? messages,
  }) async {
    try {
      final payload = <String, dynamic>{
        'id': id ?? roomId,
        'avatarId': avatarId,
        'live': live,
        'title': title,
        'statusLine': statusLine,
        if (adminSessionId != null) 'adminSessionId': adminSessionId,
        if (clientSessionId != null) 'clientSessionId': clientSessionId,
        if (previewSessionId != null) 'previewSessionId': previewSessionId,
        if (hostName != null) 'hostName': hostName,
        if (coverHint != null) 'coverHint': coverHint,
        if (productName != null) 'productName': productName,
        if (productPrice != null) 'productPrice': productPrice,
        if (productContext != null) 'productContext': productContext,
        if (hostScript != null) 'hostScript': hostScript,
        if (voiceProfileId != null) 'voiceProfileId': voiceProfileId,
        if (likeCount != null) 'likeCount': likeCount,
        if (viewerCount != null) 'viewerCount': viewerCount,
        if (messages != null) 'messages': messages,
      };
      final res = await http
          .post(
            _uri('/api/xile/room'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 5));
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      return body is Map && body['code'] == 0;
    } catch (_) {
      return false;
    }
  }

  Future<void> reportClientSession(
    String sessionId, {
    String role = 'client',
    String? id,
  }) async {
    try {
      await http
          .post(
            _uri('/api/xile/client_session'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'sessionid': sessionId,
              'roomId': id ?? roomId,
              'role': role,
            }),
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  Future<String?> replyQuestion(String question, {String productContext = ''}) async {
    try {
      final res = await http
          .post(
            _uri('/api/xile/reply'),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode({
              'question': question,
              'productContext': productContext,
            }),
          )
          .timeout(const Duration(seconds: 18));
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (body is Map && body['code'] == 0 && body['data'] is Map) {
        final text = '${(body['data'] as Map)['text'] ?? ''}'.trim();
        if (text.isNotEmpty) return text;
      }
    } catch (_) {}
    return null;
  }

  Future<String?> submitAsk(String text, {String source = 'text'}) async {
    try {
      final res = await http
          .post(
            _uri('/api/xile/ask'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'text': text,
              'source': source,
              'roomId': roomId,
            }),
          )
          .timeout(const Duration(seconds: 8));
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (body is Map && body['code'] == 0 && body['data'] is Map) {
        return '${(body['data'] as Map)['id']}';
      }
    } catch (_) {}
    return null;
  }

  Future<List<SyncAsk>> pendingAsks({String? id}) async {
    try {
      final rid = id ?? roomId ?? '';
      final res = await http
          .get(_uri('/api/xile/asks', {
            'pending': '1',
            if (rid.isNotEmpty) 'id': rid,
          }))
          .timeout(const Duration(seconds: 5));
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (body is Map && body['code'] == 0 && body['data'] is Map) {
        final list = (body['data'] as Map)['asks'];
        if (list is List) {
          return list
              .whereType<Map>()
              .map((e) => SyncAsk.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
      }
    } catch (_) {}
    return const [];
  }

  Future<AnswerResult?> markAnswered({
    required String id,
    required String answer,
    String? roomIdOverride,
  }) async {
    try {
      final res = await http
          .post(
            _uri('/api/xile/ask/answer'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'id': id,
              'answer': answer,
              'roomId': roomIdOverride ?? roomId,
            }),
          )
          .timeout(const Duration(seconds: 5));
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (body is Map && body['code'] == 0 && body['data'] is Map) {
        final d = Map<String, dynamic>.from(body['data'] as Map);
        return AnswerResult(
          clientSessionId: '${d['clientSessionId'] ?? ''}',
          previewSessionId: '${d['previewSessionId'] ?? ''}',
          adminSessionId: '${d['adminSessionId'] ?? ''}',
          roomId: '${d['roomId'] ?? ''}',
        );
      }
    } catch (_) {}
    return null;
  }

  Future<int?> bumpLikes({int delta = 1, String? id}) async {
    try {
      final res = await http
          .post(
            _uri('/api/xile/like'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'roomId': id ?? roomId,
              'delta': delta,
            }),
          )
          .timeout(const Duration(seconds: 4));
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (body is Map && body['code'] == 0 && body['data'] is Map) {
        return ((body['data'] as Map)['likeCount'] as num?)?.toInt();
      }
    } catch (_) {}
    return null;
  }

  Future<PresenceResult?> reportPresence({
    required String action,
    required String viewerId,
    String? id,
  }) async {
    try {
      final res = await http
          .post(
            _uri('/api/xile/presence'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'roomId': id ?? roomId,
              'viewerId': viewerId,
              'action': action,
            }),
          )
          .timeout(const Duration(seconds: 5));
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (body is Map && body['code'] == 0 && body['data'] is Map) {
        final d = Map<String, dynamic>.from(body['data'] as Map);
        return PresenceResult(
          viewerCount: (d['viewerCount'] as num?)?.toInt() ?? 0,
          likeCount: (d['likeCount'] as num?)?.toInt() ?? 0,
          viewerId: '${d['viewerId'] ?? viewerId}',
        );
      }
    } catch (_) {}
    return null;
  }
}

class PresenceResult {
  const PresenceResult({
    required this.viewerCount,
    required this.likeCount,
    required this.viewerId,
  });
  final int viewerCount;
  final int likeCount;
  final String viewerId;
}
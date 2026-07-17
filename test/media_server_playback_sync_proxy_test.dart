import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/media_server_playback.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/services/emby_playback_sync_service.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/jellyfin_playback_sync_service.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/media_server_transport.dart';

void main() {
  test('routes Emby and Jellyfin playback sync through the configured proxy',
      () async {
    final receivedRequests =
        <({String method, Uri uri, String body, String? token})>[];
    final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => proxy.close(force: true));
    proxy.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      receivedRequests.add((
        method: request.method,
        uri: request.uri,
        body: body,
        token: request.headers.value('x-emby-token'),
      ));
      final isEmby = request.uri.path.startsWith('/emby/');
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(isEmby
            ? {
                'UserData': {'PlayCount': 0},
              }
            : {'PlayCount': 0}));
      await request.response.close();
    });

    final embyDirectRequests = <Uri>[];
    final jellyfinDirectRequests = <Uri>[];
    final embyTarget = await _startDirectTrap(
      {
        'UserData': {'PlayCount': 0}
      },
      embyDirectRequests,
    );
    final jellyfinTarget = await _startDirectTrap(
      {'PlayCount': 0},
      jellyfinDirectRequests,
    );
    addTearDown(() => embyTarget.close(force: true));
    addTearDown(() => jellyfinTarget.close(force: true));

    MediaServerTransport.setHttpProxyOverride(
      'http://${proxy.address.address}:${proxy.port}',
    );
    addTearDown(MediaServerTransport.clearHttpProxyOverride);
    final emby = EmbyService.instance
      ..serverUrl = 'http://${embyTarget.address.address}:${embyTarget.port}'
      ..accessToken = 'emby-token'
      ..userId = 'emby-user'
      ..currentProfile = null
      ..isConnected = true;
    final jellyfin = JellyfinService.instance
      ..serverUrl =
          'http://${jellyfinTarget.address.address}:${jellyfinTarget.port}'
      ..accessToken = 'jellyfin-token'
      ..userId = 'jellyfin-user'
      ..currentProfile = null
      ..isConnected = true;
    addTearDown(() {
      emby
        ..isConnected = false
        ..serverUrl = null
        ..accessToken = null
        ..userId = null;
      jellyfin
        ..isConnected = false
        ..serverUrl = null
        ..accessToken = null
        ..userId = null;
    });
    final localHistory = WatchHistoryItem(
      filePath: 'test.mp4',
      animeName: 'Test',
      watchProgress: 0,
      lastPosition: 0,
      duration: 1000,
      lastWatchTime: DateTime.utc(2024),
    );
    final embySync = EmbyPlaybackSyncService();
    final jellyfinSync = JellyfinPlaybackSyncService();
    addTearDown(embySync.dispose);
    addTearDown(jellyfinSync.dispose);

    await embySync.syncOnPlayStart('emby-item', localHistory);
    await jellyfinSync.syncOnPlayStart('jellyfin-item', localHistory);
    await embySync.reportPlaybackStart(
      'emby-item',
      localHistory,
      playbackSession: PlaybackSession(
        itemId: 'emby-item',
        streamUrl: 'http://stream.invalid/emby',
        isTranscoding: false,
        mediaSourceId: 'emby-source',
        playSessionId: 'emby-session',
      ),
    );
    await jellyfinSync.reportPlaybackStart(
      'jellyfin-item',
      localHistory,
      playbackSession: PlaybackSession(
        itemId: 'jellyfin-item',
        streamUrl: 'http://stream.invalid/jellyfin',
        isTranscoding: false,
        mediaSourceId: 'jellyfin-source',
        playSessionId: 'jellyfin-session',
      ),
    );

    expect(receivedRequests, hasLength(4));
    expect(receivedRequests[0].method, 'GET');
    expect(
        receivedRequests[0].uri,
        Uri.parse(
          'http://${embyTarget.address.address}:${embyTarget.port}'
          '/emby/Users/emby-user/Items/emby-item',
        ));
    expect(receivedRequests[1].method, 'GET');
    expect(
        receivedRequests[1].uri,
        Uri.parse(
          'http://${jellyfinTarget.address.address}:${jellyfinTarget.port}'
          '/Users/jellyfin-user/Items/jellyfin-item/UserData',
        ));
    expect(receivedRequests[2].method, 'POST');
    expect(
        receivedRequests[2].uri,
        Uri.parse(
          'http://${embyTarget.address.address}:${embyTarget.port}'
          '/emby/Sessions/Playing',
        ));
    expect(receivedRequests[2].token, 'emby-token');
    expect(
        jsonDecode(receivedRequests[2].body),
        containsPair(
          'PlaySessionId',
          'emby-session',
        ));
    expect(receivedRequests[3].method, 'POST');
    expect(
        receivedRequests[3].uri,
        Uri.parse(
          'http://${jellyfinTarget.address.address}:${jellyfinTarget.port}'
          '/Sessions/Playing',
        ));
    expect(receivedRequests[3].token, 'jellyfin-token');
    expect(
        jsonDecode(receivedRequests[3].body),
        containsPair(
          'PlaySessionId',
          'jellyfin-session',
        ));
    expect(embyDirectRequests, isEmpty);
    expect(jellyfinDirectRequests, isEmpty);
  });
}

Future<HttpServer> _startDirectTrap(
  Map<String, Object> responseBody,
  List<Uri> receivedRequests,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    receivedRequests.add(request.uri);
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(responseBody));
    await request.response.close();
  });
  return server;
}

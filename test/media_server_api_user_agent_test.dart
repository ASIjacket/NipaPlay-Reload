@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/media_server_service_base.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  PackageInfo.setMockInitialValues(
    appName: 'NipaPlay',
    packageName: 'com.example.nipaplay',
    version: '1.0.0',
    buildNumber: '1',
    buildSignature: '',
  );

  test('Emby API uses the connection User-Agent', () async {
    final requests = await _captureLibraryRequests(
      configure: (baseUrl) {
        final service = EmbyService.instance
          ..serverUrl = baseUrl
          ..userId = 'emby-user'
          ..accessToken = 'emby-token'
          ..isConnected = true;
        addTearDown(() {
          service
            ..serverUrl = null
            ..userId = null
            ..accessToken = null
            ..isConnected = false;
        });
        return service.loadAvailableLibraries;
      },
    );

    expect(requests, [('/emby/Library/MediaFolders', 'ApiClient/6.0')]);
  });

  test('Jellyfin API uses the connection User-Agent', () async {
    final requests = await _captureLibraryRequests(
      configure: (baseUrl) {
        final service = JellyfinService.instance
          ..serverUrl = baseUrl
          ..userId = 'jellyfin-user'
          ..accessToken = 'jellyfin-token'
          ..isConnected = true;
        addTearDown(() {
          service
            ..serverUrl = null
            ..userId = null
            ..accessToken = null
            ..isConnected = false;
        });
        return service.loadAvailableLibraries;
      },
    );

    expect(requests, [('/UserViews', 'ApiClient/6.0')]);
  });
}

Future<List<(String, String?)>> _captureLibraryRequests({
  required Future<void> Function() Function(String baseUrl) configure,
}) async {
  await MediaServerServiceBase.saveConnectionUserAgent('ApiClient/6.0');
  addTearDown(() => MediaServerServiceBase.saveConnectionUserAgent(''));

  final requests = <(String, String?)>[];
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  server.listen((request) async {
    requests.add((
      request.uri.path,
      request.headers.value(HttpHeaders.userAgentHeader),
    ));
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'Items': <Object>[]}));
    await request.response.close();
  });

  final loadLibraries = configure(
    'http://${server.address.address}:${server.port}',
  );
  await loadLibraries();
  return requests;
}

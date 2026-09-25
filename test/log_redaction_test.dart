import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/utils/log_redaction.dart';

void main() {
  test('masks the Emby api_key in a logged stream URL', () {
    // Shape of the line users exported: the token was in plain text.
    expect(
      redactSecretsForLog(
        'Emby 哈希计算使用直连URL: https://emby.example/emby/Videos/190216/stream'
        '?Static=true&api_key=0123456789abcdef',
      ),
      'Emby 哈希计算使用直连URL: https://emby.example/emby/Videos/190216/stream'
      '?Static=true&api_key=<redacted>',
    );
  });

  test('keeps the other query parameters', () {
    expect(
      redactSecretsForLog(
        'https://emby.example/videos/1/original.mkv'
        '?MediaSourceId=abc&api_key=secret&Static=true',
      ),
      'https://emby.example/videos/1/original.mkv'
      '?MediaSourceId=abc&api_key=<redacted>&Static=true',
    );
  });

  test('covers the other token parameter spellings', () {
    expect(
      redactSecretsForLog(
        'a?ApiKey=1 b?X-Emby-Token=2 c?x-mediabrowser-token=3 '
        'd?access_token=4 e?token=5',
      ),
      'a?ApiKey=<redacted> b?X-Emby-Token=<redacted> '
      'c?x-mediabrowser-token=<redacted> d?access_token=<redacted> '
      'e?token=<redacted>',
    );
  });

  test('drops user and password from URLs', () {
    expect(
      redactSecretsForLog('打开 smb://user:pa55@nas.local/share/a.mkv'),
      '打开 smb://nas.local/share/a.mkv',
    );
  });

  test('leaves text without secrets alone', () {
    const plain = '[Bangumi API] Token无效，清除登录信息 status=401';
    expect(redactSecretsForLog(plain), plain);
    expect(
      redactSecretsForLog('https://example.com/path@v2?PlaySessionId=abc'),
      'https://example.com/path@v2?PlaySessionId=abc',
    );
    expect(redactSecretsForLog('mytoken=abc'), 'mytoken=abc');
  });
}

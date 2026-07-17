import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/player_abstraction/mdk_player_adapter_io.dart';

void main() {
  test('MDK runtime User-Agent overrides both FFmpeg HTTP option layers', () {
    final applied = <(String, String)>[];

    applyMdkUserAgentProperties(
      (key, value) => applied.add((key, value)),
      'OneTimeClient/3.0',
    );

    expect(
      applied,
      [
        ('avformat.user_agent', 'OneTimeClient/3.0'),
        ('avio.user_agent', 'OneTimeClient/3.0'),
      ],
    );
  });

  test('MDK HTTP proxy overrides both FFmpeg HTTP option layers', () {
    final applied = <(String, String)>[];

    applyMdkHttpProxyProperties(
      (key, value) => applied.add((key, value)),
      'http://127.0.0.1:8000',
    );

    expect(
      applied,
      [
        ('avformat.http_proxy', 'http://127.0.0.1:8000'),
        ('avio.http_proxy', 'http://127.0.0.1:8000'),
      ],
    );
  });
}

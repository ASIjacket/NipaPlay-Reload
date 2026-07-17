import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/utils/remote_media_fetcher.dart';

void main() {
  test('Rust media file size preserves native int values', () {
    expect(rustPlatformInt64ToDartInt(1024), 1024);
  });

  test('Rust media file size converts web BigInt values without truncation',
      () {
    expect(
      rustPlatformInt64ToDartInt(BigInt.parse('5000000000')),
      5000000000,
    );
  });
}

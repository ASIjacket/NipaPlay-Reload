import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/utils/decoder_manager.dart';

void main() {
  test('reports the hardware interface mpv is actually using', () {
    expect(describeMpvDecoder('d3d11va'), '硬解 - d3d11va');
    expect(describeMpvDecoder('nvdec-copy'), '硬解 - nvdec-copy');
  });

  test('reports software decoding when mpv says no', () {
    // With the hardware switch off, mpv's hwdec-current is "no". The old
    // label still read the configured MDK decoder list and showed 硬解.
    expect(describeMpvDecoder('no'), '软解 - FFmpeg');
    expect(describeMpvDecoder('NO'), '软解 - FFmpeg');
  });

  test('has no answer before mpv knows', () {
    expect(describeMpvDecoder(null), isNull);
    expect(describeMpvDecoder(''), isNull);
    expect(describeMpvDecoder('  '), isNull);
  });
}

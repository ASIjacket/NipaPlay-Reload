import '../models/emby_media_selection.dart';

EmbyReleaseIdentity parseEmbyReleaseIdentity(String name) {
  final tokens = _tokenize(name);
  final nonTechnicalTokens = tokens.where((token) => !_isTechnical(token));
  final normalizedFullName = nonTechnicalTokens.join(' ');
  final features = nonTechnicalTokens
      .where(_isFeature)
      .map((token) => token.toLowerCase())
      .toSet();
  final families = nonTechnicalTokens
      .where((token) => !_isFeature(token) && !_isReleaseFormat(token))
      .map((token) => token.toLowerCase())
      .toSet();

  return EmbyReleaseIdentity(
    normalizedFullName: normalizedFullName,
    families: families,
    features: features,
  );
}

List<String> _tokenize(String name) => name
    .trim()
    .toLowerCase()
    .replaceAll(
      RegExp(r'[\s._/\\|,:;!?+&()\[\]{}<>\-\u00b7\u2022\u2013\u2014]+'),
      ' ',
    )
    .split(RegExp(r'\s+'))
    .where((token) => token.isNotEmpty)
    .toList(growable: false);

bool _isTechnical(String token) =>
    RegExp(r'^\d{3,4}p$').hasMatch(token) ||
    const {
      '2160p',
      '1440p',
      '1080p',
      '720p',
      '576p',
      '480p',
      'h264',
      'h265',
      'hevc',
      'av1',
      'x264',
      'x265',
      'vp9',
      '10bit',
      '8bit',
      'hdr',
      'hdr10',
      'dv',
      'dovi',
      'aac',
      'flac',
      'opus',
      'ac3',
      'eac3',
    }.contains(token);

bool _isReleaseFormat(String token) => const {
      'web',
      'dl',
      'webdl',
      'webrip',
      'bluray',
      'bdrip',
      'remux',
      'raw',
      'encode',
    }.contains(token);

bool _isFeature(String token) => RegExp(
      r'[\u7b80\u7e41]|\u5185\u5c01|\u5185\u5d4c|\u5916\u6302|\u5b57\u5e55|\u53cc\u8bed|\u4e2d\u5b57',
    ).hasMatch(token);

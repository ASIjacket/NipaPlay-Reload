/// 日志脱敏：遮掉 URL 里的访问令牌和用户名密码。
///
/// 媒体服务器的播放地址把访问令牌放在查询参数里（如 Emby 的 `api_key`），
/// 日志一旦导出分享，令牌就跟着泄露。这里只改写日志文本，不影响实际请求。
library;

final RegExp _tokenQueryParam = RegExp(
  r'(^|[?&;\s,])((?:api_key|apikey|x-emby-token|x-mediabrowser-token|access_token|token)=)[^&\s"' "'" r'#,)]+',
  caseSensitive: false,
);

final RegExp _urlUserInfo = RegExp(r'([a-zA-Z][a-zA-Z0-9+.\-]*://)[^/\s@]+@');

/// 返回遮掉令牌与 URL 用户信息后的 [text]。
String redactSecretsForLog(String text) {
  if (!text.contains('=') && !text.contains('://')) return text;
  return text
      .replaceAllMapped(
        _tokenQueryParam,
        (m) => '${m[1]}${m[2]}<redacted>',
      )
      .replaceAllMapped(_urlUserInfo, (m) => m[1]!);
}

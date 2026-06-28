class SettingsKeys {
  SettingsKeys._();

  static const String appLanguageMode = 'app_language_mode';

  static const String clearDanmakuCacheOnLaunch =
      'clear_danmaku_cache_on_launch';

  static const String autoMatchDanmakuFirstSearchResultOnHashFail =
      'danmaku_auto_match_first_search_result_on_hash_fail';

  static const String autoMatchDanmakuOnPlay = 'danmaku_auto_match_on_play';

  static const String danmakuAutoLoadStrategy = 'danmaku_auto_load_strategy';

  static const String useExternalPlayer = 'external_player_enabled';

  static const String externalPlayerPath = 'external_player_path';

  static const String autoCheckUpdatesInBackground =
      'auto_check_updates_in_background';

  static const String legacyAutoCheckUpdatesOnAboutPage =
      'auto_check_updates_on_about_page';

  static const String showRemoteAccessQrCode = 'show_remote_access_qr_code';

  static const String labsEnableLargeScreenMode =
      'labs_enable_large_screen_mode';

  static const String labsShowRemoteAccessQrCode =
      'labs_show_remote_access_qr_code';

  static const String labsEnableNext2DanmakuKernel =
      'labs_enable_next2_danmaku_kernel';

  static const String labsEnableErikaPlayerKernel =
      'labs_enable_erika_player_kernel';

  static const String labsEnableNextPlusPlusEngine =
      'labs_enable_next_plus_plus_engine';

  static const String torrentDownloadDirectory = 'torrent_download_directory';

  static const String torrentRecentDownloadDirectories =
      'torrent_recent_download_directories';

  static const String torrentRecentDownloadDirectoriesMigrated =
      'torrent_recent_download_directories_migrated';

  static const String downloaderEnabled = 'downloader_enabled';

  static const String downloaderCreateFolderForTask =
      'downloader_create_folder_for_task';

  static const String downloaderAutoScanCompletedTasks =
      'downloader_auto_scan_completed_tasks';

  static const String downloaderAutoScannedCompletedTaskKeys =
      'downloader_auto_scanned_completed_task_keys';

  static const String githubProxyUrl = 'github_proxy_url';

  static const String danmakuSupersample = 'danmaku_supersample';

  /// 自定义播放器网络流 User-Agent（留空表示使用内核默认值）。
  /// MDK 内核映射到 avformat.user_agent，media_kit/libmpv 映射到 user-agent。
  static const String playerCustomUserAgent = 'player_custom_user_agent';

  /// 播放器网络流 HTTP/HTTPS 代理（如 http://127.0.0.1:7890，留空表示不使用代理）。
  /// MDK 内核映射到 avformat.http_proxy，media_kit/libmpv 映射到 http-proxy。
  static const String playerHttpProxy = 'player_http_proxy';
}

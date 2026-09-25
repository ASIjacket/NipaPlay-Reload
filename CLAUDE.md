# 本仓库相对官方上游的有意改动

上游是 `https://github.com/MCDFsteve/NipaPlay-Reload`。本文件记录**必须在每次同步上游后保留**的改动。
同步上游（`git merge upstream/main` 等）之后，请照下面的清单逐条核对。

---

## 1. `.github/workflows/build-windows.yml` — 手动构建 + 产物瘦身

**保留原因**

上游这个 workflow 只有 `workflow_call`，无法在 Actions 页面单独构建 Windows；且产物
`path: build/windows/*` 会把完整构建树 `x64/` 和免安装包解压后的同名目录一起打包，
artifact 约 1.2 GB，其中一个多 GB 没有任何消费方 —— 发布流程 `main.yml` 只取顶层的
`*.zip` / `*.exe` / `*.msix`。

改完后手动构建的 artifact 约 130 MB。

**改动内容**

`on:` 段补回手动触发入口：

```yaml
on:
  workflow_dispatch:
    inputs:
      portable-only:
        description: '产物只保留免安装版（跳过安装器和 MSIX）'
        type: boolean
        default: true
  workflow_call:
    # 刻意不暴露 portable-only：release 需要安装器和 MSIX
```

产物上传按触发方式拆成两步，替换掉上游原来那个 `Upload Windows Artifacts`：

```yaml
      - name: Upload portable Windows build
        if: inputs.portable-only
        uses: actions/upload-artifact@v4
        with:
          name: release-Windows-x64
          path: build/windows/NipaPlay_*_Windows_x64/
          if-no-files-found: error

      - name: Upload Windows Artifacts
        if: ${{ !inputs.portable-only }}
        uses: actions/upload-artifact@v4
        with:
          name: release-Windows-x64
          path: |
            build/windows/*.zip
            build/windows/*.exe
            build/windows/*.msix
          if-no-files-found: error
```

**两个容易改错的点**

- 判据必须用 `inputs.portable-only`，**不能**用 `github.event_name == 'workflow_dispatch'`：
  被 `workflow_call` 时 `event_name` 是**调用方**的事件，手动触发 `main.yml` 同样会得到
  `workflow_dispatch`，据此判断会让正式 release 丢掉安装器和 MSIX。
  `workflow_call` 段不定义该 input，未定义时求值为空，自然走完整产物分支。
- 手动分支传的是**免安装目录本身**，不是它的 `.zip`：artifact 下载下来本身就是 zip，
  再套一层要解压两次才能跑；而且内层已压过一次，外层再压等于白压（套娃 320 MB，
  直接传目录 130 MB）。

**同步后自检**

```bash
git diff --stat upstream/main..HEAD
# 期望：除 CLAUDE.md 外，只有本条的 build-windows.yml 和第 2–4 条列出的文件有差异
python3 -c "import yaml; d=yaml.safe_load(open('.github/workflows/build-windows.yml')); print(list(d[True].keys()))"
# 期望：['workflow_dispatch', 'workflow_call']
```

---

## 2. Emby 播放进度同步修复

**保留原因**

- 拉取：部分 Emby 服务器（如本仓库用户的）对看到一半的条目返回 `PlayCount: 0` 且
  **不带** `LastPlayedDate`，上游要求两者都有，服务器进度一律被丢弃。
- 拉取超时：上游在视频就绪后才发请求，此时播放器正全速缓冲，请求常在 10 秒超时内
  回不来（用户日志实测）。
- 上报：上游用 `_position % 1000 < 100` 抽样，读到的是 await 之后的位置，前面耗时
  超过约 100ms 这一轮就静默不传；暂停时又每帧带着 `IsPaused: false` 连发。

**改动内容**

- `lib/services/emby_playback_sync_service.dart`：顶层函数 `hasEmbyResumeProgress`
  （`PlaybackPositionTicks > 0` 即算有进度）、`preferEmbyServerResume`（有
  `LastPlayedDate` 比时间，没有则取更靠后的位置，绝不倒退本地进度）、
  `shouldUploadEmbyProgress`（只在播放中、按墙钟 5 秒节流）；`EmbyProgressPrefetch`
  与 `prefetchServerProgress`（开始加载媒体时预取服务器进度，`syncOnPlayStart` 取用，
  最多等 10 秒）；`_getServerPlaybackProgress` / `_makeAuthenticatedRequest` 多了
  `timeout` 参数；以及几条 `[EmbySync]` 日志。
- `lib/utils/video_player_state.dart`：字段 `_lastEmbyProgressUploadMs`。
- `lib/utils/video_player_state/video_player_state_danmaku.dart`：`_updateWatchHistory`
  里的 Emby 上报块改用 `shouldUploadEmbyProgress`（Jellyfin 块未动）。
- `lib/utils/video_player_state/video_player_state_player_setup.dart`：恢复
  `_initializeWatchHistory` 失败时的日志；`initializePlayer` 识别到 Emby 流时调用
  `prefetchServerProgress`。
- `test/emby_playback_sync_resume_test.dart`。

**同步后自检**

上游若改动了这些位置，先看上游是否已修好同一问题：修好了就取上游、删掉本条；
没修就按上面重新应用。然后：

```bash
flutter test test/emby_playback_sync_resume_test.dart
```

---

## 3. Emby 弹幕匹配：哈希、集数、按季记忆

**保留原因**

- 哈希：设置了自定义 UA 时，`RemoteMediaFetcher` 的 HttpClient 默认 UA 固定为
  `NipaPlay/1.0`，dart:io 跟随 302 时不沿用请求头里的 UA，网盘直链按 UA 放行即 403；
  而且起播要等哈希失败（8–22 秒）。
- 只选番剧不选集时，`_matchWithDandanPlay` 用 `episodeNumber` 键查
  `_getAnimeEpisodes` 的结果（键实为 `episodeIndex`），总落到第 1 集。
- 上游的 `EmbyEpisodeMappingService` 只写不读，同一季每集都要重新匹配。

**改动内容**

- `lib/utils/remote_media_fetcher.dart`：HttpClient 默认 UA 用实际 UA；`fetchHead`
  增加 `abort`。
- `lib/services/emby_dandanplay_matcher.dart`：`findEpisodeByIndex`；
  `waitForVideoHash`（最多等 8 秒，超时中止下载）；本季记忆的读取（哈希之后、
  搜索之前）、写入（仅弹窗里亲自选的；弹窗结果加 `episodeExplicit`）、
  `rememberManualMatch` / `undoRememberedMatch` / `seriesMemoryForItem` /
  `forgetSeriesMemoryForItem`。
- 新增 `lib/services/emby_danmaku_series_memory.dart`、
  `lib/utils/emby_danmaku_memory_actions.dart`。
- `lib/themes/nipaplay/widgets/danmaku_settings_menu.dart`、
  `lib/themes/cupertino/widgets/player_menu/cupertino_danmaku_settings_pane.dart`：
  手动匹配后记住本季（"仅本集"撤回），有记忆时显示"忘记本季匹配"。

**同步后自检**

```bash
flutter test test/remote_media_fetcher_user_agent_test.dart test/remote_media_fetcher_abort_test.dart \
  test/emby_hash_wait_test.dart test/emby_dandanplay_episode_lookup_test.dart \
  test/emby_danmaku_series_memory_test.dart
```

---

## 4. 其他小修复

- `lib/services/server_history_sync_service.dart`：同步来的记录不再把 Emby 集号写进
  弹幕 `episodeId`；合并抽成 `mergeSyncedHistoryItem`，孤立的 `episodeId` 清掉。
- 日志脱敏：新增 `lib/utils/log_redaction.dart`，`DebugLogService._addLogEntry` 与
  `_redactMediaUrlForLog`（`lib/utils/video_player_state.dart`）调用它。
- mpv 内核解码器显示：`describeMpvDecoder`（`lib/utils/decoder_manager.dart`）、
  `Player.readMpvPropertyAsync` / 适配器 `readMpvProperty`、播放信息里
  `hwdec-current=no` 显示"软件"、切换硬解开关后刷新显示
  （`video_player_state_preferences.dart`）。

**同步后自检**

```bash
flutter test test/server_history_sync_merge_test.dart test/log_redaction_test.dart \
  test/mpv_decoder_label_test.dart
```

---

## 同步上游的做法

```bash
git remote add upstream https://github.com/MCDFsteve/NipaPlay-Reload   # 首次
git fetch upstream main
git merge upstream/main
```

若 `build-windows.yml` 冲突，以本文件记录的版本为准重新应用，不要直接取上游版本。
第 2–4 条涉及的文件冲突时，先看上游是否已修好同一问题：修好了就取上游、删掉对应
条目；没修就按记录重新应用，再跑该条的"同步后自检"。

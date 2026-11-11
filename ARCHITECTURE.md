# ReelNest 架构设计（原 MyVidhub）

> 本地影视库管理 + 播放器。参考 VidHub：读取 Kodi/Jellyfin 风格的 **NFO + 海报** 元数据，海报墙浏览，内置强兼容播放器。
> 目标平台：**Android 平板（第一优先）**、Android 手机、iPhone/iPad、Windows、macOS。

---

## 1. 技术选型（结论）

| 层 | 选型 | 理由 |
|---|---|---|
| UI 框架 | **Flutter 3.x (Dart)** | 一套代码覆盖 Android / iOS / Windows / macOS；自绘引擎，平板大屏 120Hz 流畅；自适应布局方便 |
| 播放内核 | **media_kit（libmpv + FFmpeg）** | 与 VidHub/Infuse 同级的格式兼容：MKV、HEVC/H.265、AV1、10bit HDR、DTS/TrueHD 软解、ASS/SSA 特效字幕、PGS 图形字幕、多音轨；各平台硬解 |
| 本地数据库 | **SQLite（`sqlite3` 包，原生库随 App 打包）** | 媒体库索引、观看进度、收藏；手写 SQL，免代码生成；后续可加 FTS5 全文搜索 |
| 状态管理 | **Riverpod** | 可测试、异步友好 |
| 路由 | Navigator（M1）→ 需要深链接时再上 go_router | 目前页面层级浅，保持简单 |
| NFO 解析 | **xml** 包 + 自写容错解析器 | NFO 常有不规范 XML，需要容错 |
| 图片缓存 | M1：`ResizeImage` 按显示尺寸原生降采样解码；M4：网络源海报落盘缓存 | 本地 4K 海报也只解码到显示尺寸，滚动不卡 |
| 网络源 | WebDAV（`webdav_client`）、SMB（libsmb2 FFI）、本地目录 | 覆盖 NAS 常见场景 |

**为什么不选其他方案：**
- Python（Kivy/Flet）：Android 平板上视频播放和流畅度都不行。
- Electron / Tauri：桌面好，但 Android 平板支持弱，WebView 播放器解码能力受限（不支持 MKV/DTS/ASS）。
- React Native：桌面端（Win/Mac）生态弱，播放器组件兼容性不如 mpv。
- 原生分别写（Kotlin + Swift + C#）：效果最好但工作量 ×3。

Flutter + libmpv 是"一套代码 + 播放器够强"的最优平衡点。

---

## 2. 整体分层

```
┌───────────────────────────────────────────────────────────┐
│  UI 层 (Flutter Widgets)                                   │
│  海报墙 · 详情页 · 剧集/季 · 播放器 · 设置 · 搜索            │
│  自适应：手机单栏 / 平板双栏(NavigationRail) / 桌面侧边栏      │
│  焦点系统：支持遥控器/键盘 D-pad（Android 电视盒子也能用）    │
├───────────────────────────────────────────────────────────┤
│  应用层 (Riverpod Providers / Use Cases)                   │
│  LibraryService · ScanService · PlaybackService · Search   │
├───────────────────────────────────────────────────────────┤
│  领域层 (纯 Dart，无平台依赖)                               │
│  Movie · TvShow · Season · Episode · Person · MediaFile    │
│  NfoParser · FilenameParser(S01E02 / 年份识别)             │
├───────────────────────────────────────────────────────────┤
│  数据层                                                    │
│  ┌──────────────┐ ┌────────────────┐ ┌──────────────────┐ │
│  │ SQLite(drift)│ │ 缩略图缓存目录  │ │ 设置(shared_prefs)│ │
│  └──────────────┘ └────────────────┘ └──────────────────┘ │
├───────────────────────────────────────────────────────────┤
│  存储源抽象 MediaSource（统一接口）                          │
│  LocalSource │ WebDavSource │ SmbSource │ (后期) Alist/Emby │
├───────────────────────────────────────────────────────────┤
│  平台层                                                    │
│  media_kit(libmpv) · Android SAF/存储权限 · libsmb2 FFI     │
└───────────────────────────────────────────────────────────┘
```

### 存储源统一接口

```dart
abstract class MediaSource {
  String get id;
  Future<List<SourceEntry>> list(String path);          // 列目录
  Future<Uint8List> readBytes(String path, {int? max}); // 读 NFO / 图片
  Future<String> playableUri(String path);              // 给播放器的地址
}
```

- **本地**：`playableUri` 直接返回文件路径。
- **WebDAV**：返回 `https://user:pass@host/path`（或 header 鉴权），mpv 原生支持 HTTP Range 拖动。
- **SMB**：App 内起一个 **本地 HTTP 代理**（`127.0.0.1:随机端口`），代理把 Range 请求转成 libsmb2 读取 → mpv 播放 `http://127.0.0.1/...`。这样 mpv 不需要编译 SMB 支持，拖动进度也流畅。

---

## 3. NFO 元数据处理（核心功能）

### 支持的目录结构（Kodi / Jellyfin / Emby / tinyMediaManager 通用）

```
电影/
  阿凡达 (2009)/
    阿凡达 (2009).mkv
    阿凡达 (2009).nfo        ← 或 movie.nfo
    poster.jpg / 阿凡达 (2009)-poster.jpg
    fanart.jpg / -fanart.jpg
    clearlogo.png
    *.ass / *.srt            ← 外挂字幕

剧集/
  绝命毒师 (2008)/
    tvshow.nfo
    poster.jpg  fanart.jpg
    season01-poster.jpg
    Season 1/
      绝命毒师 - S01E01.mkv
      绝命毒师 - S01E01.nfo   ← <episodedetails>
      绝命毒师 - S01E01-thumb.jpg
```

### 解析字段

- `<movie>`：title, originaltitle, year, plot, rating(s), runtime, genre[], tag[], country, director, actor[name/role/thumb], uniqueid(tmdb/imdb), set(合集)
- `<tvshow>`：同上 + premiered, status
- `<episodedetails>`：title, season, episode, plot, aired, thumb

### 容错策略
1. 去掉 BOM、非法控制字符后再解析 XML。
2. NFO 末尾附带 URL 的情况（老版 Kodi 格式）→ 截取 XML 部分。
3. 无 NFO → `FilenameParser` 从文件名解析标题/年份/季集，作为兜底。
4. （后期可选）无 NFO 时调用 TMDB 在线刮削并**回写 NFO**。

---

## 4. 媒体库扫描

```
ScanService (运行在后台 Isolate，不卡 UI)
 ├─ 递归遍历源目录 → 按视频扩展名筛选
 ├─ 按目录归组：电影目录 / 剧集目录(含 tvshow.nfo 或 SxxExx)
 ├─ 解析 NFO → 写入 SQLite（事务批量写）
 ├─ 海报 → 降采样生成缩略图 → 存 cache/thumbs/{hash}_{size}.webp
 └─ 增量扫描：记录 文件 mtime+size，未变化跳过
```

- 首次扫描进度条；之后打开 App **秒开**（全部读本地 SQLite + 本地缩略图）。
- 手动刷新 / 下拉刷新 / 定时增量扫描。

### 数据库主要表

```
sources(id, type, name, root, credentials_ref)
media_items(id, source_id, kind[movie|show], title, original_title, year,
            plot, rating, genres, poster_thumb, fanart_thumb, nfo_path, dir_path, mtime)
seasons(id, show_id, season_no, poster_thumb)
episodes(id, show_id, season_no, episode_no, title, plot, file_path, thumb)
media_files(id, item_id|episode_id, path, size, duration)
people(id, name, thumb) / item_people(item_id, person_id, role, order)
playback_state(file_id, position_ms, duration_ms, finished, updated_at)
favorites(item_id)
media_fts (FTS5: title, original_title, actors, plot)
```

凭据（SMB/WebDAV 密码）存 **flutter_secure_storage**（Android Keystore / iOS Keychain / Windows DPAPI），不进 SQLite。

---

## 5. UI 设计（平板优先）

| 断点 | 布局 |
|---|---|
| < 600dp（手机竖屏） | 底部导航 + 3 列海报 |
| 600–1200dp（平板） | 左侧 NavigationRail + 5–7 列海报；详情页左海报右信息；剧集页 季列表 + 集列表 双栏 |
| > 1200dp（桌面 / 平板横屏大屏） | 侧边栏 + 8+ 列海报，鼠标悬停预览 |

页面：
- **首页**：继续观看、最近添加、电影、剧集、合集
- **海报墙**：排序（标题/年份/评分/添加时间）、筛选（类型/年份/已看）
- **详情页**：fanart 背景模糊、演员横滑、版本选择、外挂字幕
- **播放器**：手势（左亮度/右音量/横滑进度/双击暂停）、倍速、音轨/字幕切换、字幕延迟/大小、画面比例、记忆进度、自动下一集
- **设置**：媒体源管理、扫描、播放器（硬解开关、默认字幕语言）

流畅度保障：
- 海报墙用 `GridView.builder` 懒加载 + 只加载缩略图 + `cacheWidth` 解码
- 扫描/解析/缩略图生成全部放 Isolate
- 冷启动只读 SQLite，不碰网络

---

## 6. 平台注意事项

| 平台 | 要点 |
|---|---|
| **Android 平板** | Android 11+ 访问任意目录需 `MANAGE_EXTERNAL_STORAGE`（侧载可用；上架 Play 则用 SAF 选目录）；支持 U 盘/OTG；mediacodec 硬解；横屏优先 |
| Android 手机 | 同上，布局走手机断点 |
| iOS / iPadOS | 本地文件通过"文件"App 导入或 App 沙盒；主要靠 SMB/WebDAV |
| Windows | 直接读本地盘/网络映射盘；D3D11 硬解 |
| macOS | 直接读本地盘；VideoToolbox 硬解；需要签名才能分发 |

---

## 7. 项目目录结构

```
MyVidhub/
  lib/
    main.dart
    app/            路由、主题、自适应外壳
    core/           工具类、日志、错误处理
    domain/         实体 + NfoParser + FilenameParser（纯 Dart，可单测）
    data/
      db/           drift 表定义与 DAO
      sources/      local / webdav / smb + 本地 HTTP 代理
      cache/        缩略图
    services/       scan / library / playback
    features/
      home/  library/  detail/  player/  settings/  search/
  test/             NFO 解析、文件名解析的单元测试（附样例 NFO）
  android/ ios/ windows/ macos/
```

---

## 8. 开发路线

| 阶段 | 内容 | 产出 |
|---|---|---|
| **M1 基础** | Flutter 工程、本地目录源、NFO 解析 + 单测、SQLite、扫描、海报墙、详情页 | 平板上能看到海报墙 |
| **M2 播放** | media_kit 播放器、手势、字幕/音轨、进度记忆、继续观看 | 能流畅播 MKV/HEVC/ASS |
| **M3 剧集** | 剧集/季/集结构、自动下一集、搜索、筛选排序 | 完整本地影视库 |
| **M4 网络源** | WebDAV、SMB（libsmb2 + 本地代理） | 直连 NAS |
| **M5 增强** | TMDB 刮削补全、多端进度同步（可选 WebDAV 存同步文件）、Android TV 遥控适配 | |

---

## 9. 开发环境（当前 Mac 需安装）

- Flutter SDK（当前未安装）：`brew install --cask flutter`
- Android Studio（Android SDK + 模拟器 / 真机 adb 调试）
- Xcode（iOS / macOS 构建）
- Windows 版需在 Windows 机器上 `flutter build windows`（或用 CI）

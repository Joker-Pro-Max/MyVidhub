# MyVidhub

本地影视库管理：读取 Kodi / Jellyfin / Emby / tinyMediaManager 整理的 **NFO + 海报**，以海报墙方式浏览。
Flutter 开发，一套代码支持 Android 平板 / 手机、iPad / iPhone、Windows、macOS。架构见 [ARCHITECTURE.md](ARCHITECTURE.md)。

> **⚠️ 许可声明：仅限个人、非商业使用**
>
> 本项目采用 [PolyForm Noncommercial License 1.0.0](LICENSE.md) 授权，**不是**常规意义上的开源软件。
>
> - ✅ 允许：个人学习、研究、自用；在非商业前提下修改和分享（须保留本许可证与版权声明）
> - ❌ 禁止：任何商业用途，包括但不限于售卖本软件或其修改版、内置到商业产品或服务中、以付费方式分发、用于盈利性运营
>
> 如需商业授权，请通过 GitHub 联系作者。Copyright © 2026 Joker-Pro-Max。

## M1：媒体库 ✅

- 添加本地文件夹（Android 会引导开启"所有文件访问权限"）
- 后台 Isolate 扫描：识别电影 / 剧集 / 季 / 集，重扫时保留原有条目、清理已删除的条目
- 容错 NFO 解析：BOM、未转义 `&`、XML 后附 URL、截断文件、`<ratings>` 新格式
- 没有 NFO 时从文件名 / 目录名推断（`S01E02`、`1x02`、`第05集`、`第二季`、`片名 (年份)`、`CD1/CD2`）
- 图片：poster / folder / fanart / clearlogo / `seasonXX-poster` / 集缩略图 `-thumb` / `.actors/` 演员头像
- 自适应 UI：手机底部导航 3 列；平板侧边导航 5–7 列；桌面展开侧边栏
- 详情页：背景图、评分、类型、简介、导演、演员、文件 / 版本；剧集按季切换

## M2：播放器 ✅

- 内核 media_kit（libmpv + FFmpeg），各平台硬解；MKV / HEVC / AV1 / 10bit / DTS / TrueHD
- 字幕：内封 + 外挂（同名或 `Subs/` 目录自动加载），ASS 特效由 libass 原样渲染；默认优先简体中文；可调延迟、大小
- 音轨切换（显示语言、编码、声道）、倍速 0.5–3x、画面比例（适应 / 填充 / 拉伸 / 16:9 / 4:3 / 2.35:1）
- 手势（平板 / 手机）：左侧上下滑亮度、右侧音量、横滑拖进度、双击左右 ±10 秒、双击中间暂停、长按 2 倍速、锁屏
- 键盘（桌面 / 遥控器）：空格暂停、←→ ±10 秒（Shift ±60）、↑↓ 音量、F 全屏、M 静音、N/P 下一集/上一集、Esc 返回
- 进度记忆：每 5 秒和退出时保存，再次打开自动续播并提示「从头播放」；看到 92% 记为已看完
- 剧集连播：播完 5 秒倒计时自动下一集，播放中可选集
- 首页「继续观看」（剧集看完一集自动推荐下一集）；海报进度条 / 已看标记；详情页「继续播放 / 继续 S01E03」「标记已看」
- 剧集列表长按某一集可切换已看 / 未看

## 自动更新 ✅

- 安卓端启动后自动检查 [GitHub Releases](https://github.com/Joker-Pro-Max/MyVidhub/releases)（每 6 小时最多一次），发现新版本弹窗说明，App 内下载、校验 SHA-256 后调起系统安装器
- 设置 → 版本与更新：查看当前版本、手动检查

发布新版本（自动改版本号、打包、打 tag、上传 Release）：

```bash
tool/release.sh 1.0.2 "更新说明"
```

## 运行

```bash
flutter pub get
```

macOS / iOS 需要 CocoaPods（`brew install cocoapods`）：

```bash
flutter run -d macos
```

Android 平板：安装 Android Studio（含 SDK），平板开启 USB 调试后：

```bash
flutter run -d <设备ID>
```

开发时可以用 `--dart-define=DEMO_DIR=/媒体库路径` 启动时自动添加并扫描一个文件夹（仅 debug 构建）。

## 测试

```bash
flutter test
```

各尺寸截图（真机渲染，输出到 SHOT_DIR）：

```bash
flutter test integration_test/screenshots_test.dart -d macos --dart-define=DEMO_DIR=/媒体库路径 --dart-define=SHOT_DIR=/输出目录
```

播放器端到端测试（真实解码，需要媒体库里有可播放的视频）：

```bash
flutter test integration_test/player_test.dart -d macos --dart-define=DEMO_DIR=/媒体库路径 --dart-define=SHOT_DIR=/输出目录
```

## 目录

```
lib/
  main.dart                 启动、主题
  app/                      自适应外壳、Riverpod providers
  domain/                   NFO 解析、文件名解析、扩展名规则（纯 Dart）
  data/db/                  SQLite 表结构与查询
  data/sources/             媒体源接口 + 本地实现（M4 加 WebDAV / SMB）
  services/                 扫描器、后台扫描任务
  features/                 home / library / detail / settings / player
  widgets/                  海报卡片、图片组件
test/                       单元测试（含模拟媒体库生成器）
integration_test/           多尺寸截图、播放器端到端、自动更新联网测试
tool/release.sh             一键发布
```

## 许可证

[PolyForm Noncommercial License 1.0.0](LICENSE.md) — 禁止商业使用。中文说明仅为便于理解，以英文许可证原文为准。

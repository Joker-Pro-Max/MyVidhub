import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/models.dart';
import '../features/home/home_page.dart';
import '../features/library/library_page.dart';
import '../features/search/search_page.dart';
import '../features/settings/settings_page.dart';
import '../features/settings/update_ui.dart';
import '../ui/components.dart';
import '../ui/tokens.dart';
import 'update_controller.dart';

/// 页面内容需要为浮动导航预留的空间（内容可以从导航下方滚过）。
class ShellInsets extends InheritedWidget {
  const ShellInsets({super.key, required this.top, required this.bottom, required super.child});

  final double top;
  final double bottom;

  static ShellInsets of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellInsets>() ??
      ShellInsets(
        top: MediaQuery.paddingOf(context).top + 16,
        bottom: MediaQuery.paddingOf(context).bottom + 16,
        child: const SizedBox.shrink(),
      );

  @override
  bool updateShouldNotify(ShellInsets old) => old.top != top || old.bottom != bottom;
}

/// 自适应外壳：
/// - 平板 / 桌面：顶部浮动的毛玻璃标签胶囊（首页 / 电影 / 剧集），设置收在右上角齿轮
/// - 手机：底部毛玻璃导航条（图标 + 文字，无指示胶囊）
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;

  static const _tabs = [
    (icon: Icons.home_outlined, selected: Icons.home_rounded, label: '首页'),
    (icon: Icons.movie_outlined, selected: Icons.movie_rounded, label: '电影'),
    (icon: Icons.tv_outlined, selected: Icons.tv_rounded, label: '剧集'),
    (icon: Icons.settings_outlined, selected: Icons.settings_rounded, label: '设置'),
    (icon: Icons.search_rounded, selected: Icons.search_rounded, label: '搜索'),
  ];

  static const _settings = 3;
  static const _search = 4;

  /// 手机底栏的排列顺序（下标指向 _tabs）。
  static const _phoneOrder = [0, 1, 2, _search, _settings];

  @override
  void initState() {
    super.initState();
    // 启动几秒后静默检查更新，避免拖慢冷启动
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) ref.read(updateProvider.notifier).autoCheck();
    });
  }

  void _select(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    ref.listen(updateProvider, (prev, next) {
      if (next.shouldPrompt) {
        ref.read(updateProvider.notifier).promptShown();
        UpdateDialog.show(context);
      }
    });

    final ff = FormFactor.of(context);
    final pad = MediaQuery.paddingOf(context);
    final pages = IndexedStack(
      index: _index,
      children: [
        HomePage(onSeeAll: (k) => _select(k == MediaKind.movie ? 1 : 2)),
        const LibraryPage(kind: MediaKind.movie),
        const LibraryPage(kind: MediaKind.show),
        const SettingsPage(),
        SearchPage(active: _index == _search),
      ],
    );

    // 桌面：⌘F / Ctrl+F 打开搜索
    final shortcuts = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () => _select(_search),
      const SingleActivator(LogicalKeyboardKey.keyF, control: true): () => _select(_search),
    };

    if (ff.isPhone) {
      const barH = 62.0;
      return Scaffold(
        extendBody: true,
        body: ShellInsets(top: pad.top + 12, bottom: pad.bottom + barH + 16, child: pages),
        bottomNavigationBar: _PhoneBar(index: _index, onSelect: _select, height: barH),
      );
    }

    const navH = 64.0;
    return CallbackShortcuts(
      bindings: shortcuts,
      child: Scaffold(
        body: Stack(
          children: [
            ShellInsets(top: pad.top + navH + 8, bottom: pad.bottom + 24, child: pages),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _TopBar(index: _index, onSelect: _select, height: navH, gutter: ff.gutter),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.index, required this.onSelect, required this.height, required this.gutter});

  final int index;
  final ValueChanged<int> onSelect;
  final double height;
  final double gutter;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return DecoratedBox(
      // 让滚到导航下方的内容渐隐，文字始终可读
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Palette.shade(0.78), Palette.shade(0)],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(gutter, top + 10, gutter - 4, 18),
        child: SizedBox(
          height: height - 18,
          child: Row(
            children: [
              const _Wordmark(),
              const Spacer(),
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Palette.surface1.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Palette.hairline),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < 3; i++)
                          _TopTab(label: _AppShellState._tabs[i].label, selected: index == i, onTap: () => onSelect(i)),
                      ],
                    ),
                  ),
                ),
              ),
              const Spacer(),
              RoundIconButton(
                icon: Icons.search_rounded,
                tooltip: '搜索',
                selected: index == _AppShellState._search,
                overArtwork: true,
                size: 42,
                onPressed: () => onSelect(_AppShellState._search),
              ),
              const SizedBox(width: 10),
              RoundIconButton(
                icon: Icons.settings_outlined,
                tooltip: '设置',
                selected: index == _AppShellState._settings,
                overArtwork: true,
                size: 42,
                onPressed: () => onSelect(_AppShellState._settings),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(color: Palette.light, borderRadius: BorderRadius.circular(7)),
        child: const Icon(Icons.play_arrow_rounded, size: 20, color: Palette.onLight),
      ),
      const SizedBox(width: 10),
      Text('MyVidhub', style: TypeScale.headline.copyWith(fontSize: 17, letterSpacing: -0.2)),
    ],
  );
}

class _TopTab extends StatelessWidget {
  const _TopTab({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    radius: 20,
    child: AnimatedContainer(
      duration: Motion.of(context, Motion.fast),
      curve: Motion.curve,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? Palette.light : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TypeScale.callout.copyWith(
          fontSize: 15,
          color: selected ? Palette.onLight : Palette.text2,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    ),
  );
}

class _PhoneBar extends StatelessWidget {
  const _PhoneBar({required this.index, required this.onSelect, required this.height});
  final int index;
  final ValueChanged<int> onSelect;
  final double height;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          height: height + bottom,
          padding: EdgeInsets.only(bottom: bottom),
          decoration: BoxDecoration(
            color: Palette.surface1.withValues(alpha: 0.82),
            border: const Border(top: BorderSide(color: Palette.hairline)),
          ),
          child: Row(
            children: [
              for (final i in _AppShellState._phoneOrder)
                Expanded(
                  child: Pressable(
                    onTap: () => onSelect(i),
                    radius: 12,
                    hoverOverlay: false,
                    child: SizedBox(
                      height: height,
                      width: double.infinity,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            index == i ? _AppShellState._tabs[i].selected : _AppShellState._tabs[i].icon,
                            size: 24,
                            color: index == i ? Palette.light : Palette.text3,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _AppShellState._tabs[i].label,
                            style: TypeScale.caption.copyWith(
                              fontSize: 11,
                              color: index == i ? Palette.light : Palette.text3,
                              fontWeight: index == i ? FontWeight.w600 : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../data/db/models.dart';
import '../features/home/home_page.dart';
import '../features/library/library_page.dart';
import '../features/settings/settings_page.dart';

/// 自适应外壳：
/// - 手机（< 600dp）：底部导航
/// - 平板（600–1200dp）：左侧 NavigationRail
/// - 桌面 / 大屏平板横屏（≥ 1200dp）：展开的侧边栏
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _destinations = [
    (icon: Icons.home_outlined, selected: Icons.home_rounded, label: '首页'),
    (icon: Icons.movie_outlined, selected: Icons.movie_rounded, label: '电影'),
    (icon: Icons.tv_outlined, selected: Icons.tv_rounded, label: '剧集'),
    (icon: Icons.settings_outlined, selected: Icons.settings_rounded, label: '设置'),
  ];

  void _select(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final pages = IndexedStack(
      index: _index,
      children: [
        HomePage(onSeeAll: (k) => _select(k == MediaKind.movie ? 1 : 2)),
        const LibraryPage(kind: MediaKind.movie),
        const LibraryPage(kind: MediaKind.show),
        const SettingsPage(),
      ],
    );

    if (width < 600) {
      return Scaffold(
        body: SafeArea(bottom: false, child: pages),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _select,
          height: 64,
          destinations: [
            for (final d in _destinations)
              NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selected), label: d.label),
          ],
        ),
      );
    }

    final extended = width >= 1200;
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Row(children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: _select,
            extended: extended,
            minExtendedWidth: 200,
            labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
            groupAlignment: -0.9,
            leading: Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 20),
              child: extended
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.play_circle_fill_rounded, color: theme.colorScheme.primary, size: 32),
                      const SizedBox(width: 10),
                      Text('MyVidhub',
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    ])
                  : Icon(Icons.play_circle_fill_rounded, color: theme.colorScheme.primary, size: 36),
            ),
            destinations: [
              for (final d in _destinations)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selected),
                  label: Text(d.label),
                ),
            ],
          ),
          VerticalDivider(width: 1, color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
          Expanded(child: pages),
        ]),
      ),
    );
  }
}

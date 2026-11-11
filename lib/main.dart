import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app/app_shell.dart';
import 'app/providers.dart';
import 'data/db/library_db.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  final dbPath = p.join(dir.path, 'library.db');
  final db = LibraryDb.open(dbPath);

  final container = ProviderContainer(overrides: [
    dbPathProvider.overrideWithValue(dbPath),
    dbProvider.overrideWithValue(db),
  ]);

  // 开发用：flutter run --dart-define=DEMO_DIR=/path/to/library 自动添加并扫描
  const demoDir = String.fromEnvironment('DEMO_DIR');
  if (kDebugMode && demoDir.isNotEmpty && !db.sources().any((s) => s.root == demoDir)) {
    final id = db.addSource(type: 'local', name: p.basename(demoDir), root: demoDir);
    container.read(scanProvider.notifier).scan(id);
  }

  runApp(UncontrolledProviderScope(container: container, child: const MyVidhubApp()));
}

class MyVidhubApp extends StatelessWidget {
  const MyVidhubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MyVidhub',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      themeMode: ThemeMode.dark,
      home: const AppShell(),
    );
  }
}

ThemeData buildTheme() {
  const bg = Color(0xFF0E1014);
  const accent = Color(0xFFF2B33D);
  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: accent,
    onPrimary: const Color(0xFF1F1500),
    surface: bg,
    surfaceContainerLowest: const Color(0xFF0A0B0E),
    surfaceContainerLow: const Color(0xFF14161B),
    surfaceContainer: const Color(0xFF181B21),
    surfaceContainerHigh: const Color(0xFF1F232A),
    surfaceContainerHighest: const Color(0xFF272B33),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    visualDensity: VisualDensity.standard,
    cardTheme: CardThemeData(
      color: scheme.surfaceContainer,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: bg,
      indicatorColor: accent.withValues(alpha: 0.18),
      selectedIconTheme: const IconThemeData(color: accent),
      selectedLabelTextStyle: const TextStyle(color: accent, fontWeight: FontWeight.w600),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: accent.withValues(alpha: 0.18),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide.none,
      backgroundColor: scheme.surfaceContainerHigh,
      selectedColor: accent.withValues(alpha: 0.22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
    }),
  );
}

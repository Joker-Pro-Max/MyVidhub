import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app/app_shell.dart';
import 'app/providers.dart';
import 'data/db/library_db.dart';
import 'ui/tokens.dart';

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

/// 全局主题：只负责把 Material 控件压到设计令牌上（去水波纹、去色调表面）。
/// 视觉规范见 DESIGN.md，组件见 lib/ui/。
ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: Palette.light,
    onPrimary: Palette.onLight,
    secondary: Palette.text2,
    onSecondary: Palette.onLight,
    surface: Palette.bg,
    onSurface: Palette.text,
    onSurfaceVariant: Palette.text2,
    surfaceContainerLowest: Palette.bg,
    surfaceContainerLow: Palette.surface1,
    surfaceContainer: Palette.surface1,
    surfaceContainerHigh: Palette.surface2,
    surfaceContainerHighest: Palette.surface3,
    outline: Palette.text3,
    outlineVariant: Palette.hairline,
    error: Palette.danger,
    surfaceTint: Colors.transparent,
  );
  final text = const TextTheme(
    displaySmall: TypeScale.display,
    headlineMedium: TypeScale.largeTitle,
    headlineSmall: TypeScale.largeTitle,
    titleLarge: TypeScale.title,
    titleMedium: TypeScale.headline,
    titleSmall: TypeScale.callout,
    bodyLarge: TypeScale.body,
    bodyMedium: TypeScale.callout,
    bodySmall: TypeScale.caption,
    labelLarge: TypeScale.callout,
    labelMedium: TypeScale.caption,
    labelSmall: TypeScale.overline,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    textTheme: text,
    scaffoldBackgroundColor: Palette.bg,
    canvasColor: Palette.bg,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: Palette.glow(0.04),
    focusColor: Palette.glow(0.10),
    dividerTheme: const DividerThemeData(color: Palette.hairline, thickness: 1, space: 1),
    iconTheme: const IconThemeData(color: Palette.text),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: Palette.light,
      linearTrackColor: Palette.glow(0.18),
      circularTrackColor: Palette.glow(0.08),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStateProperty.all(4),
      radius: const Radius.circular(4),
      thumbColor: WidgetStateProperty.all(Palette.glow(0.25)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: Palette.surface3, borderRadius: BorderRadius.circular(8)),
      textStyle: TypeScale.caption.copyWith(color: Palette.text),
      waitDuration: const Duration(milliseconds: 600),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Palette.surface2,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.group)),
      textStyle: TypeScale.callout,
      labelTextStyle: WidgetStateProperty.all(TypeScale.callout.copyWith(fontSize: 15)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Palette.surface2,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.dialog)),
      titleTextStyle: TypeScale.title,
      contentTextStyle: TypeScale.body.copyWith(color: Palette.text2),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Palette.surface3,
      contentTextStyle: TypeScale.callout,
      actionTextColor: Palette.light,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.card)),
      width: 420,
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Palette.text,
        textStyle: TypeScale.callout.copyWith(fontWeight: FontWeight.w600),
        shape: const StadiumBorder(),
        minimumSize: const Size(64, 44),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Palette.surface1,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.card), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        borderSide: const BorderSide(color: Palette.light, width: 1.5),
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: Palette.light,
      inactiveTrackColor: Palette.glow(0.2),
      thumbColor: Palette.light,
      overlayColor: Palette.glow(0.12),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
    }),
  );
}

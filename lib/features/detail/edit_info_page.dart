import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/app_settings.dart';
import '../../app/providers.dart';
import '../../data/db/models.dart';
import '../../organizer/code.dart';
import '../../organizer/filename_title.dart';
import '../../organizer/meta.dart';
import '../../organizer/organize.dart';
import '../../organizer/pipeline.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../widgets/av_blur.dart';
import '../../widgets/media_image.dart';
import '../organize/organize_storage.dart';

enum _Mode {
  local('本地数据'),
  online('在线刮削');

  const _Mode(this.label);
  final String label;
}

/// 编辑信息：使用本地数据（手动修改）或在线刮削（选刮削源 → 搜索 → 选候选）。
/// 结果写回影片旁的 NFO 和图片（旧文件先备份，可在整理页撤销），然后重新扫描。
class EditInfoPage extends ConsumerStatefulWidget {
  const EditInfoPage({super.key, required this.detail, this.startOnline = false});
  final MediaDetail detail;
  final bool startOnline;

  static Future<bool?> open(BuildContext context, MediaDetail d, {bool online = false}) =>
      Navigator.of(context).push<bool>(FadeRoute(builder: (_) => EditInfoPage(detail: d, startOnline: online)));

  /// 只有本地文件夹里的电影能写回 NFO。
  static String? unsupportedReason(MediaDetail d, SourceRow? source) {
    if (source == null) return '找不到所属的文件夹';
    if (source.isNetwork) return 'NAS 上的影片暂不支持编辑信息';
    if (d.kind == MediaKind.show) return '剧集暂不支持编辑信息';
    if (d.files.isEmpty) return '没有找到视频文件';
    if (!File(d.files.first.path).existsSync()) {
      return '视频文件不存在（可能已被移动、删除，或所在磁盘没有连接），无法刮削';
    }
    return null;
  }

  @override
  ConsumerState<EditInfoPage> createState() => _EditInfoPageState();
}

class _EditInfoPageState extends ConsumerState<EditInfoPage> {
  late _Mode _mode = widget.startOnline ? _Mode.online : _Mode.local;
  MediaDetail get d => widget.detail;
  String get _video => d.files.first.path;
  String? get _code => extractCode(p.basename(_video));

  // 本地数据
  late final _title = TextEditingController(text: d.title);
  late final _original = TextEditingController(text: d.originalTitle ?? '');
  late final _year = TextEditingController(text: d.year?.toString() ?? '');
  late final _rating = TextEditingController(text: d.rating?.toStringAsFixed(1) ?? '');
  late final _genres = TextEditingController(text: d.genres.join('、'));
  late final _directors = TextEditingController(text: d.directors.join('、'));
  late final _plot = TextEditingController(text: d.plot ?? '');

  // 在线刮削
  ScraperChoice _choice = ScraperChoice.auto;
  late final _query = TextEditingController();
  late final _qYear = TextEditingController(text: d.year?.toString() ?? '');
  bool _searching = false;
  bool _applying = false;
  String? _message;
  List<ScrapedMeta>? _candidates;

  @override
  void initState() {
    super.initState();
    _choice = ref.read(appSettingsProvider).autoScrape || _code == null ? ScraperChoice.tmdb : ScraperChoice.auto;
    _syncQuery();
  }

  void _syncQuery() {
    _query.text = switch (_choice) {
      ScraperChoice.javbus || ScraperChoice.r18dev => _code ?? '',
      ScraperChoice.tmdb => d.title,
      ScraperChoice.auto => _code ?? d.title,
    };
  }

  @override
  void dispose() {
    for (final c in [_title, _original, _year, _rating, _genres, _directors, _plot, _query, _qYear]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _tmdbKey => effectiveTmdbKey(ref.read(dbProvider));

  List<String> _splitList(String s) =>
      s.split(RegExp(r'[、,，/|]')).map((x) => x.trim()).where((x) => x.isNotEmpty).toList();

  /// 写回 NFO（和图片），保存撤销记录，重新扫描。
  Future<void> _write(ScrapedMeta meta, {required bool images}) async {
    if (!File(_video).existsSync()) throw const FileSystemException('视频文件不存在，无法写入资料');
    final source = ref.read(dbProvider).source(d.sourceId)!;
    final ops = <UndoOp>[];
    final rep = await refreshMetadata(
      _video,
      meta,
      ops,
      await metadataBackupDir(),
      nfoPath: d.nfoPath,
      writeImages: images,
    );
    await (await organizeUndoStore()).save(UndoLog(createdAt: DateTime.now(), root: source.root, ops: ops));
    ref.read(scanProvider.notifier).scan(d.sourceId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(rep.warnings.isEmpty ? '已更新「${meta.title}」，正在刷新片库' : '已更新资料（${rep.warnings.first}）'),
    ));
    Navigator.of(context).pop(true);
  }

  Future<void> _saveLocal() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _message = '标题不能为空');
      return;
    }
    setState(() {
      _applying = true;
      _message = null;
    });
    final meta = ScrapedMeta(
      source: 'local',
      code: _code,
      title: title,
      originalTitle: _original.text.trim().isEmpty ? null : _original.text.trim(),
      plot: _plot.text.trim().isEmpty ? null : _plot.text.trim(),
      year: int.tryParse(_year.text.trim()),
      releaseDate: d.premiered,
      runtimeMins: d.runtime,
      rating: double.tryParse(_rating.text.trim()),
      genres: _splitList(_genres.text),
      directors: _splitList(_directors.text),
      actors: [for (final a in d.actors) ScrapedActor(a.name, a.thumb)],
      studio: d.studios.firstOrNull,
      label: d.tags.firstOrNull,
      series: d.setName,
    );
    try {
      await _write(meta, images: false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _applying = false;
          _message = '保存失败：$e';
        });
      }
    }
  }

  Future<void> _search() async {
    final q = _query.text.trim();
    if (_choice == ScraperChoice.tmdb && _tmdbKey.trim().isEmpty) {
      setState(() => _message = '先在「设置 › 刮削」里填写 TMDB API Key');
      return;
    }
    if (q.isEmpty) {
      setState(() => _message = _choice.needsCode ? '请输入番号' : '请输入片名或番号');
      return;
    }
    setState(() {
      _searching = true;
      _message = null;
      _candidates = null;
    });
    final code = extractCode(q) ?? (_choice.needsCode ? q.toUpperCase() : null);
    final list = await searchCandidates(
      _choice,
      code: code,
      title: q,
      year: int.tryParse(_qYear.text.trim()),
      tmdbKey: _tmdbKey,
    );
    if (!mounted) return;
    setState(() {
      _searching = false;
      _candidates = list;
      if (list.isEmpty) _message = '${_choice.label} 没有查到结果，换个刮削源或改一下搜索词试试';
    });
  }

  Future<void> _apply(ScrapedMeta m) async {
    setState(() {
      _applying = true;
      _message = null;
    });
    try {
      final full = await resolveCandidate(m, _tmdbKey) ?? m;
      await _write(full, images: true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _applying = false;
          _message = '更新失败：$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = FormFactor.of(context).gutter;
    final pad = MediaQuery.paddingOf(context);
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.fromLTRB(g, pad.top + 12, g, pad.bottom + 40),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Transform.translate(
                  offset: const Offset(-8, 0),
                  child: RoundIconButton(
                    icon: Icons.close_rounded,
                    tooltip: '关闭',
                    onPressed: _applying ? null : () => Navigator.of(context).maybePop(),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('编辑信息', style: TypeScale.largeTitle),
                const SizedBox(height: 6),
                Text(p.basename(_video), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TypeScale.callout.copyWith(color: Palette.text2)),
                const SizedBox(height: 24),
                Transform.translate(
                  offset: const Offset(-4, 0),
                  child: FilterPills<_Mode>(
                    items: _Mode.values,
                    selected: _mode,
                    label: (m) => m.label,
                    onSelect: (m) => setState(() {
                      _mode = m;
                      _message = null;
                    }),
                  ),
                ),
                const SizedBox(height: 20),
                if (_mode == _Mode.local) ..._localForm() else ..._onlineForm(),
                if (_message != null) ...[
                  const SizedBox(height: 16),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.info_outline_rounded, size: 18, color: Palette.text2),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_message!, style: TypeScale.callout.copyWith(color: Palette.text2))),
                  ]),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _localForm() => [
        GroupedList(
          footer: '保存后写入影片旁的 NFO（原 NFO 会先备份，可在「刮削并整理」页撤销）。演员、厂牌、合集保持不变。',
          children: [
            _Field(label: '标题', controller: _title),
            _Field(label: '原名', controller: _original, hint: '可选'),
            _Field(label: '年份', controller: _year, hint: '例如 2014', keyboard: TextInputType.number),
            _Field(label: '评分', controller: _rating, hint: '0–10', keyboard: const TextInputType.numberWithOptions(decimal: true)),
            _Field(label: '类型', controller: _genres, hint: '用顿号或逗号分隔'),
            _Field(label: '导演', controller: _directors, hint: '可选'),
            _Field(label: '简介', controller: _plot, hint: '可选', multiline: true),
          ],
        ),
        const SizedBox(height: 24),
        Row(children: [
          PillButton(label: _applying ? '正在保存…' : '保存', icon: _applying ? null : Icons.check_rounded, onPressed: _applying ? null : _saveLocal),
          if (_applying) ...[const SizedBox(width: 16), const Spinner()],
        ]),
      ];

  List<Widget> _onlineForm() {
    final needsCode = _choice.needsCode;
    final locked = ref.watch(appSettingsProvider).autoScrape;
    return [
      Text('刮削源'.toUpperCase(), style: TypeScale.overline),
      const SizedBox(height: 8),
      if (locked)
        Text('自动刮削已开启，使用在线影视数据（TMDB）。要用 JavBus / R18.dev，请到「设置 › 刮削」关闭自动刮削。',
            style: TypeScale.callout.copyWith(color: Palette.text2))
      else ...[
      Transform.translate(
        offset: const Offset(-4, 0),
        child: FilterPills<ScraperChoice>(
          items: ScraperChoice.values,
          selected: _choice,
          label: (c) => c.label,
          onSelect: (c) => setState(() {
            _choice = c;
            _candidates = null;
            _message = null;
            _syncQuery();
          }),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        switch (_choice) {
          ScraperChoice.auto => '有番号时先查 JavBus，缺简介用 R18.dev 补，再查不到用 TMDB',
          ScraperChoice.javbus => '按番号查询，资料最全（演员、类型、封面）；会标记为 AV',
          ScraperChoice.r18dev => '按番号查询，有英文简介和日文原名；会标记为 AV',
          ScraperChoice.tmdb => '按片名搜索，适合普通电影；会列出多个结果供你挑选',
        },
        style: TypeScale.caption.copyWith(color: Palette.text3),
      ),
      ],
      const SizedBox(height: 18),
      GroupedList(children: [
        _Field(
          label: needsCode ? '番号' : '搜索',
          controller: _query,
          hint: needsCode ? '例如 SSIS-001' : '片名或番号',
          onSubmitted: (_) => _search(),
        ),
        if (_choice == ScraperChoice.tmdb || _choice == ScraperChoice.auto)
          _Field(label: '年份', controller: _qYear, hint: '可选，能提高准确度', keyboard: TextInputType.number),
      ]),
      const SizedBox(height: 20),
      Row(children: [
        PillButton(
          label: _searching ? '正在搜索…' : '搜索',
          icon: _searching ? null : Icons.search_rounded,
          onPressed: _searching || _applying ? null : _search,
        ),
        if (_searching) ...[const SizedBox(width: 16), const Spinner()],
      ]),
      if (_candidates != null && _candidates!.isNotEmpty) ...[
        const SizedBox(height: 28),
        Text('选择正确的结果'.toUpperCase(), style: TypeScale.overline),
        const SizedBox(height: 10),
        for (final c in _candidates!)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _Candidate(meta: c, busy: _applying, onUse: () => _apply(c)),
          ),
      ],
    ];
  }
}

class _Candidate extends StatelessWidget {
  const _Candidate({required this.meta, required this.busy, required this.onUse});
  final ScrapedMeta meta;
  final bool busy;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final img = meta.posterUrl ?? meta.coverUrl;
    final info = [
      switch (meta.source) { 'javbus' => 'JavBus', 'r18dev' => 'R18.dev', 'tmdb' => 'TMDB', _ => meta.source },
      if (meta.code != null) meta.code!,
      if (meta.year != null) '${meta.year}',
      if (meta.runtimeMins != null) '${meta.runtimeMins} 分钟',
      if (meta.rating != null) '★ ${meta.rating!.toStringAsFixed(1)}',
    ].join('  ·  ');
    final plot = meta.plotOrFallback();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Palette.surface1, borderRadius: BorderRadius.circular(Radii.group)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 72,
            height: 108,
            child: AvBlur(
              isAv: meta.source == 'javbus' || meta.source == 'r18dev',
              sigma: 10,
              child: MediaImage(path: img, decodeWidth: 72, placeholder: PosterPlaceholder(title: meta.title)),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(meta.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TypeScale.headline),
            if (meta.originalTitle != null && meta.originalTitle != meta.title) ...[
              const SizedBox(height: 2),
              Text(meta.originalTitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TypeScale.caption),
            ],
            const SizedBox(height: 6),
            Text(info, maxLines: 1, overflow: TextOverflow.ellipsis, style: TypeScale.caption.copyWith(color: Palette.text3)),
            if (plot != null) ...[
              const SizedBox(height: 6),
              Text(plot, maxLines: 2, overflow: TextOverflow.ellipsis, style: TypeScale.caption.copyWith(height: 1.45)),
            ],
            const SizedBox(height: 10),
            PillButton(label: busy ? '正在更新…' : '使用这个', compact: true, onPressed: busy ? null : onUse),
          ]),
        ),
      ]),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.hint,
    this.keyboard,
    this.multiline = false,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboard;
  final bool multiline;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: multiline ? 14 : 0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(crossAxisAlignment: multiline ? CrossAxisAlignment.start : CrossAxisAlignment.center, children: [
            SizedBox(width: 64, child: Text(label, style: TypeScale.callout.copyWith(fontSize: 15))),
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: multiline ? TextInputType.multiline : keyboard,
                minLines: multiline ? 4 : 1,
                maxLines: multiline ? 10 : 1,
                autocorrect: false,
                onSubmitted: onSubmitted,
                cursorColor: Palette.light,
                style: TypeScale.callout.copyWith(fontSize: 15, height: multiline ? 1.55 : 1.3),
                decoration: InputDecoration(
                  isCollapsed: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintText: hint,
                  hintStyle: TypeScale.callout.copyWith(fontSize: 15, color: Palette.text3),
                ),
              ),
            ),
          ]),
        ),
      );
}

/// 「使用在线影视数据」：按默认顺序（番号 → JavBus / R18.dev，否则 TMDB）直接更新资料。
Future<void> quickRescrape(BuildContext context, WidgetRef ref, MediaDetail d) async {
  final messenger = ScaffoldMessenger.of(context);
  final db = ref.read(dbProvider);
  final video = d.files.first.path;
  if (!File(video).existsSync()) {
    messenger.showSnackBar(const SnackBar(content: Text('视频文件不存在，无法刮削')));
    return;
  }
  final code = extractCode(p.basename(video));
  final key = effectiveTmdbKey(db);
  messenger.showSnackBar(const SnackBar(content: Text('正在获取在线资料…'), duration: Duration(seconds: 30)));
  if (key.trim().isEmpty) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(const SnackBar(content: Text('使用在线影视数据需要 TMDB API Key（设置 › 刮削）')));
    return;
  }
  final (title, year, _) = titleForSearch(video, d.title, d.year);
  final meta = await scrapeWith(ScraperChoice.tmdb, code: code, title: title, year: year, tmdbKey: key);
  messenger.hideCurrentSnackBar();
  if (meta == null) {
    messenger.showSnackBar(SnackBar(
      content: Text(code != null
          ? 'TMDB 查不到番号片。到「设置 › 刮削」关闭自动刮削后，可以在「编辑信息」里选 JavBus / R18.dev'
          : 'TMDB 没有查到，可以在「编辑信息」里改一下片名再搜'),
    ));
    return;
  }
  try {
    final ops = <UndoOp>[];
    final rep = await refreshMetadata(video, meta, ops, await metadataBackupDir(), nfoPath: d.nfoPath);
    final root = db.source(d.sourceId)!.root;
    await (await organizeUndoStore()).save(UndoLog(createdAt: DateTime.now(), root: root, ops: ops));
    ref.read(scanProvider.notifier).scan(d.sourceId);
    messenger.showSnackBar(SnackBar(
      content: Text('已更新为「${meta.title}」${rep.warnings.isEmpty ? '' : '（${rep.warnings.first}）'}'),
    ));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('更新失败：$e')));
  }
}

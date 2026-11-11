import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_shell.dart';
import '../../app/providers.dart';
import '../../data/db/models.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../widgets/av_blur.dart';
import '../../widgets/media_image.dart';
import '../../widgets/poster_card.dart';
import '../detail/detail_page.dart';
import '../player/play_actions.dart';
import '../player/play_item.dart';
import 'actor_page.dart';
import 'genre_page.dart';

/// 搜索：片名 / 原名 / 导演 / 演员 / 单集标题。没输入时按类型浏览。
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key, required this.active});

  /// 当前是否是可见的标签页（切换过来时自动弹出键盘）。
  final bool active;

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  static const _recentKey = 'recent_searches';
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  String _query = '';

  @override
  void didUpdateWidget(SearchPage old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      if (mounted) setState(() => _query = v.trim());
    });
  }

  void _setQuery(String q) {
    _controller.text = q;
    _controller.selection = TextSelection.collapsed(offset: q.length);
    setState(() => _query = q);
    _remember(q);
  }

  List<String> get _recent {
    try {
      final raw = ref.read(dbProvider).setting(_recentKey);
      return raw == null ? const [] : (jsonDecode(raw) as List).cast<String>();
    } catch (_) {
      return const [];
    }
  }

  void _remember(String q) {
    final t = q.trim();
    if (t.isEmpty) return;
    final list = [t, ..._recent.where((r) => r != t)].take(8).toList();
    ref.read(dbProvider).setSetting(_recentKey, jsonEncode(list));
  }

  void _forget(String q) {
    final list = _recent.where((r) => r != q).toList();
    ref.read(dbProvider).setSetting(_recentKey, list.isEmpty ? null : jsonEncode(list));
    setState(() {});
  }

  void _openItem(MediaSummary m) {
    _remember(_query);
    DetailPage.open(context, m.id);
  }

  @override
  Widget build(BuildContext context) {
    final insets = ShellInsets.of(context);
    final ff = FormFactor.of(context);
    final g = ff.gutter;
    final results = ref.watch(searchProvider(_query));
    final hasQuery = _query.isNotEmpty;
    final empty = results.movies.isEmpty && results.shows.isEmpty && results.people.isEmpty && results.episodes.isEmpty;

    // 最佳匹配：片名包含搜索词的第一个条目（结果已按前缀匹配排序）
    final all = [...results.movies, ...results.shows];
    final q = _query.toLowerCase();
    final top = all
        .where((m) => m.title.toLowerCase().contains(q) || (m.originalTitle?.toLowerCase().contains(q) ?? false))
        .firstOrNull;
    final movies = results.movies.where((m) => m.id != top?.id).toList();
    final shows = results.shows.where((m) => m.id != top?.id).toList();

    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(g, insets.top + (ff.isPhone ? 8 : 20), g, hasQuery ? 28 : 36),
          sliver: SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: _SearchField(
                  controller: _controller,
                  focus: _focus,
                  onChanged: _onChanged,
                  onSubmitted: _remember,
                  onClear: () {
                    _controller.clear();
                    setState(() => _query = '');
                    _focus.requestFocus();
                  },
                ),
              ),
            ),
          ),
        ),

        // ---------------- 没有输入：最近搜索 + 按类型浏览
        if (!hasQuery) ...[
          if (_recent.isNotEmpty)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(g, 0, g, 36),
              sliver: SliverToBoxAdapter(child: _recentBlock()),
            ),
          ..._genreGrid(g, ff),
        ]

        // ---------------- 没有结果
        else if (empty)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(g, 24, g, 0),
            sliver: SliverToBoxAdapter(
              child: Center(
                child: Column(children: [
                  const Icon(Icons.search_off_rounded, size: 40, color: Palette.text3),
                  const SizedBox(height: 16),
                  Text('没有找到「$_query」', style: TypeScale.title),
                  const SizedBox(height: 8),
                  Text('试试片名的一部分、英文原名，或导演、演员的名字',
                      textAlign: TextAlign.center, style: TypeScale.callout.copyWith(color: Palette.text2)),
                ]),
              ),
            ),
          )

        // ---------------- 结果
        else ...[
          if (top != null)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(g, 0, g, 40),
              sliver: SliverToBoxAdapter(
                child: _TopResult(
                  item: top,
                  onOpen: () => _openItem(top),
                  onPlay: () {
                    _remember(_query);
                    playItem(context, ref, top.id);
                  },
                ),
              ),
            ),
          if (movies.isNotEmpty) ...[
            SliverToBoxAdapter(child: _CountHeader(title: '电影', count: movies.length)),
            PosterGrid(items: movies, onTap: _openItem, bottom: 32),
          ],
          if (shows.isNotEmpty) ...[
            SliverToBoxAdapter(child: _CountHeader(title: '剧集', count: shows.length)),
            PosterGrid(items: shows, onTap: _openItem, bottom: 32),
          ],
          if (results.people.isNotEmpty) ...[
            SliverToBoxAdapter(child: _CountHeader(title: '演员', count: results.people.length)),
            SliverToBoxAdapter(
              child: _PeopleRow(
                people: results.people,
                onTap: (person) {
                  _remember(_query);
                  ActorPage.open(context, person.name);
                },
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 36)),
          ],
          if (results.episodes.isNotEmpty) ...[
            SliverToBoxAdapter(child: _CountHeader(title: '单集', count: results.episodes.length)),
            SliverToBoxAdapter(
              child: _EpisodeHits(
                hits: results.episodes,
                onPlay: (h) {
                  _remember(_query);
                  playItem(context, ref, h.showId, path: h.episode.path);
                },
              ),
            ),
          ],
        ],
        SliverToBoxAdapter(child: SizedBox(height: insets.bottom + 24)),
      ],
    );
  }

  Widget _recentBlock() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('最近搜索'.toUpperCase(), style: TypeScale.overline),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final r in _recent)
            Pressable(
              onTap: () => _setQuery(r),
              onLongPress: () => _forget(r),
              radius: 20,
              semanticLabel: '搜索 $r',
              child: Container(
                height: 40,
                padding: const EdgeInsets.only(left: 14, right: 16),
                decoration: BoxDecoration(
                  color: Palette.surface1,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Palette.hairline),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.history_rounded, size: 17, color: Palette.text3),
                  const SizedBox(width: 8),
                  Text(r, style: TypeScale.callout),
                ]),
              ),
            ),
        ]),
      ]);

  List<Widget> _genreGrid(double g, FormFactor ff) {
    final tiles = ref.watch(genreTilesProvider);
    if (tiles.isEmpty) {
      return [
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: g),
          sliver: SliverToBoxAdapter(
            child: Text('搜索片名、英文原名、导演、演员或单集标题',
                textAlign: TextAlign.center, style: TypeScale.callout.copyWith(color: Palette.text2)),
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(g, 0, g, 14),
        sliver: SliverToBoxAdapter(child: Text('按类型浏览'.toUpperCase(), style: TypeScale.overline)),
      ),
      SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: g),
        sliver: SliverGrid.builder(
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: ff.isPhone ? 220 : 300,
            childAspectRatio: 16 / 9,
            crossAxisSpacing: ff.isPhone ? 12 : 18,
            mainAxisSpacing: ff.isPhone ? 12 : 18,
          ),
          itemCount: tiles.length,
          itemBuilder: (context, i) => _GenreTile(tile: tiles[i], onTap: () => GenrePage.open(context, tiles[i].genre)),
        ),
      ),
    ];
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focus,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([controller, focus]),
        builder: (context, _) {
          final on = focus.hasFocus;
          return AnimatedContainer(
            duration: Motion.of(context, Motion.fast),
            curve: Motion.curve,
            height: 56,
            padding: const EdgeInsets.only(left: 20, right: 8),
            decoration: BoxDecoration(
              color: on ? Palette.surface2 : Palette.surface1,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: on ? Palette.glow(0.4) : Palette.hairline, width: on ? 1.5 : 1),
              boxShadow: on ? [BoxShadow(color: Palette.glow(0.06), blurRadius: 24)] : null,
            ),
            child: Row(children: [
              Icon(Icons.search_rounded, size: 24, color: on ? Palette.text : Palette.text2),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focus,
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                  textInputAction: TextInputAction.search,
                  cursorColor: Palette.light,
                  cursorWidth: 2,
                  style: TypeScale.headline.copyWith(fontSize: 18, fontWeight: FontWeight.w500),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: '电影、剧集、演员、导演',
                    hintStyle: TypeScale.headline.copyWith(fontSize: 18, fontWeight: FontWeight.w400, color: Palette.text3),
                  ),
                ),
              ),
              if (controller.text.isNotEmpty)
                RoundIconButton(icon: Icons.close_rounded, tooltip: '清除', size: 36, onPressed: onClear),
            ]),
          );
        },
      );
}

class _CountHeader extends StatelessWidget {
  const _CountHeader({required this.title, required this.count});
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final g = FormFactor.of(context).gutter;
    return Padding(
      padding: EdgeInsets.fromLTRB(g, 0, g, 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
        Text(title, style: TypeScale.title),
        const SizedBox(width: 8),
        Text('$count', style: TypeScale.title.copyWith(color: Palette.text3, fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

/// 最佳匹配：剧照 + 片名 + 信息 + 播放。
class _TopResult extends StatelessWidget {
  const _TopResult({required this.item, required this.onOpen, required this.onPlay});
  final MediaSummary item;
  final VoidCallback onOpen;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final ff = FormFactor.of(context);
    final meta = [
      item.kind == MediaKind.movie ? '电影' : '剧集',
      if (item.year != null) '${item.year}',
      ...item.genres.take(2),
      if (item.rating != null) '★ ${item.rating!.toStringAsFixed(1)}',
    ].join('  ·  ');

    final image = ClipRRect(
      borderRadius: BorderRadius.circular(Radii.card),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.card),
            border: Border.all(color: Palette.hairline),
          ),
          child: AvBlur(
            isAv: item.isAv,
            child: MediaImage(
              path: item.fanart ?? item.poster,
              decodeWidth: 480,
              placeholder: PosterPlaceholder(title: item.title),
            ),
          ),
        ),
      ),
    );

    final text = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text('最佳匹配'.toUpperCase(), style: TypeScale.overline),
      const SizedBox(height: 8),
      Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TypeScale.largeTitle),
      if (item.originalTitle != null && item.originalTitle != item.title) ...[
        const SizedBox(height: 4),
        Text(item.originalTitle!, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TypeScale.callout.copyWith(color: Palette.text2)),
      ],
      const SizedBox(height: 10),
      Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: TypeScale.callout.copyWith(color: Palette.text2)),
      const SizedBox(height: 20),
      Wrap(spacing: 10, runSpacing: 10, children: [
        PillButton(label: '播放', icon: Icons.play_arrow_rounded, onPressed: onPlay),
        PillButton(label: '详情', primary: false, onPressed: onOpen),
      ]),
    ]);

    return Pressable(
      onTap: onOpen,
      radius: Radii.card,
      hoverOverlay: false,
      child: ff.isPhone
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [image, const SizedBox(height: 16), text])
          : Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              SizedBox(width: ff == FormFactor.desktop ? 440 : 380, child: image),
              const SizedBox(width: 32),
              Expanded(child: text),
            ]),
    );
  }
}

class _GenreTile extends StatelessWidget {
  const _GenreTile({required this.tile, required this.onTap});
  final GenreTile tile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        radius: Radii.group,
        semanticLabel: tile.genre,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Radii.group),
          child: Stack(fit: StackFit.expand, children: [
            MediaImage(
              path: tile.image,
              decodeWidth: 300,
              placeholder: const ColoredBox(color: Palette.surface2),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [Palette.shade(0.15), Palette.shade(0.82)],
                ),
                borderRadius: BorderRadius.circular(Radii.group),
                border: Border.all(color: Palette.hairline),
              ),
            ),
            Positioned(
              left: 16,
              bottom: 14,
              right: 16,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(tile.genre, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TypeScale.title.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('${tile.count} 部', style: TypeScale.caption.copyWith(color: Palette.text)),
              ]),
            ),
          ]),
        ),
      );
}

class _PeopleRow extends StatelessWidget {
  const _PeopleRow({required this.people, required this.onTap});
  final List<PersonHit> people;
  final void Function(PersonHit) onTap;

  @override
  Widget build(BuildContext context) {
    final g = FormFactor.of(context).gutter;
    return SizedBox(
      height: 140,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(g, 8, g, 0),
        itemCount: people.length,
        separatorBuilder: (_, _) => const SizedBox(width: 22),
        itemBuilder: (context, i) {
          final person = people[i];
          return Pressable(
            onTap: () => onTap(person),
            radius: 12,
            hoverOverlay: false,
            child: SizedBox(
              width: 88,
              child: Column(children: [
                PersonAvatar(name: person.name, thumb: person.thumb, size: 80),
                const SizedBox(height: 10),
                Text(person.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TypeScale.callout.copyWith(fontSize: 13)),
                Text('${person.itemCount} 部', style: TypeScale.caption.copyWith(fontSize: 12)),
              ]),
            ),
          );
        },
      ),
    );
  }
}

class _EpisodeHits extends StatelessWidget {
  const _EpisodeHits({required this.hits, required this.onPlay});
  final List<EpisodeHit> hits;
  final void Function(EpisodeHit) onPlay;

  @override
  Widget build(BuildContext context) {
    final ff = FormFactor.of(context);
    final w = ff.isPhone ? 220.0 : 260.0;
    return SizedBox(
      height: w * 9 / 16 + 70,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(ff.gutter, 8, ff.gutter, 0),
        itemCount: hits.length,
        separatorBuilder: (_, _) => const SizedBox(width: 18),
        itemBuilder: (context, i) {
          final h = hits[i];
          return SizedBox(
            width: w,
            child: Pressable(
              onTap: () => onPlay(h),
              radius: Radii.card,
              hoverOverlay: false,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.card),
                  child: SizedBox(
                    width: w,
                    height: w * 9 / 16,
                    child: Stack(fit: StackFit.expand, children: [
                      MediaImage(
                        path: h.episode.thumb,
                        decodeWidth: w,
                        placeholder: PosterPlaceholder(title: h.episode.title, icon: Icons.play_arrow_rounded),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(Radii.card),
                          border: Border.all(color: Palette.hairline),
                        ),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 10),
                Text('${h.showTitle} · ${episodeLabel(h.episode).split(' · ').first}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TypeScale.overline),
                const SizedBox(height: 3),
                Text(h.episode.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TypeScale.callout),
              ]),
            ),
          );
        },
      ),
    );
  }
}

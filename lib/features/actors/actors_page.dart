import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/actor_thumb_controller.dart';
import '../../app/app_shell.dart';
import '../../app/providers.dart';
import '../../data/db/models.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../home/empty_library.dart';
import '../search/actor_page.dart';

final allActorsProvider = Provider<List<PersonHit>>((ref) {
  ref.watch(libraryRevisionProvider);
  return ref.watch(dbProvider).allActors();
});

/// 演员：片库里出现过的所有演员，按参演部数排序；点开看其全部作品。
class ActorsPage extends ConsumerStatefulWidget {
  const ActorsPage({super.key});

  @override
  ConsumerState<ActorsPage> createState() => _ActorsPageState();
}

class _ActorsPageState extends ConsumerState<ActorsPage> {
  final _filter = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(sourcesProvider).isEmpty) return const EmptyLibrary();
    final all = ref.watch(allActorsProvider);
    final at = ref.watch(actorThumbProvider);
    final missing = all.where((a) => (a.thumb ?? '').isEmpty).length;
    final q = _q.toLowerCase();
    final list = q.isEmpty ? all : all.where((a) => a.name.toLowerCase().contains(q)).toList();
    final insets = ShellInsets.of(context);
    final ff = FormFactor.of(context);
    final g = ff.gutter;

    return CustomScrollView(
      key: const PageStorageKey('actors'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(g, insets.top + 8, g, 18),
          sliver: SliverToBoxAdapter(
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              const Text('演员', style: TypeScale.largeTitle),
              const SizedBox(width: 10),
              Text('${all.length}', style: TypeScale.title.copyWith(color: Palette.text3)),
              const SizedBox(width: 12),
              if (at.running)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('${at.done}/${at.total}',
                      style: TypeScale.caption.copyWith(color: Palette.text3)),
                  const SizedBox(width: 8),
                  RoundIconButton(
                    icon: Icons.stop_rounded,
                    tooltip: '停止补全',
                    size: 36,
                    onPressed: () => ref.read(actorThumbProvider.notifier).cancel(),
                  ),
                ])
              else if (missing > 0)
                ff.isPhone
                    ? RoundIconButton(
                        icon: Icons.person_search_rounded,
                        tooltip: '联网补全 $missing 位演员的头像',
                        size: 40,
                        onPressed: () => ref.read(actorThumbProvider.notifier).run(),
                      )
                    : PillButton(
                        label: '补全头像 · $missing',
                        icon: Icons.person_search_rounded,
                        primary: false,
                        compact: true,
                        onPressed: () => ref.read(actorThumbProvider.notifier).run(),
                      ),
              const Spacer(),
              if (all.length > 12)
                SizedBox(
                  width: ff.isPhone ? 150 : 240,
                  height: 40,
                  child: TextField(
                    controller: _filter,
                    onChanged: (v) => setState(() => _q = v.trim()),
                    cursorColor: Palette.light,
                    style: TypeScale.callout.copyWith(fontSize: 15),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Palette.text3),
                      prefixIconConstraints: const BoxConstraints(minWidth: 40),
                      hintText: '筛选演员',
                      hintStyle: TypeScale.callout.copyWith(fontSize: 15, color: Palette.text3),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(color: Palette.glow(0.35)),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
        if (!at.running && at.message != null)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(g, 0, g, 12),
            sliver: SliverToBoxAdapter(
              child: Text(at.message!, style: TypeScale.caption.copyWith(color: Palette.text3)),
            ),
          ),
        if (all.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(g),
                child: Text('片库的 NFO 里还没有演员信息。刮削后就会出现在这里。',
                    textAlign: TextAlign.center, style: TypeScale.body.copyWith(color: Palette.text2)),
              ),
            ),
          )
        else if (list.isEmpty)
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: g),
            sliver: SliverToBoxAdapter(
              child: Text('没有名字包含「$_q」的演员', style: TypeScale.body.copyWith(color: Palette.text2)),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(g, 0, g, insets.bottom + 24),
            sliver: SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: ff.isPhone ? 112 : 140,
                mainAxisExtent: ff.isPhone ? 150 : 178,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: list.length,
              itemBuilder: (context, i) => _ActorTile(person: list[i], avatar: ff.isPhone ? 84.0 : 104.0),
            ),
          ),
      ],
    );
  }
}

class _ActorTile extends StatelessWidget {
  const _ActorTile({required this.person, required this.avatar});
  final PersonHit person;
  final double avatar;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: () => ActorPage.open(context, person.name),
        radius: Radii.card,
        semanticLabel: person.name,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(children: [
            PersonAvatar(name: person.name, thumb: person.thumb, size: avatar),
            const SizedBox(height: 10),
            Text(person.name,
                maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TypeScale.callout),
            const SizedBox(height: 2),
            Text('${person.itemCount} 部', style: TypeScale.caption),
          ]),
        ),
      );
}

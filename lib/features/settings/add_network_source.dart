import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/sources/network_config.dart';
import '../../data/sources/source_factory.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import 'folder_browser.dart';

/// 添加 SMB / WebDAV：填写地址和账号 → 连接 → 浏览并选择影视文件夹 → 扫描。
class AddNetworkSourcePage extends ConsumerStatefulWidget {
  const AddNetworkSourcePage({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(FadeRoute(builder: (_) => const AddNetworkSourcePage()));

  @override
  ConsumerState<AddNetworkSourcePage> createState() => _AddNetworkSourcePageState();
}

class _AddNetworkSourcePageState extends ConsumerState<AddNetworkSourcePage> {
  NetworkKind _kind = NetworkKind.smb;
  final _address = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _address.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  NetworkConfig? _config() {
    final user = _user.text.trim();
    final pass = _pass.text;
    if (_kind == NetworkKind.webdav) return NetworkConfig.parseWebDav(_address.text, username: user, password: pass);
    final host = NetworkConfig.parseSmbHost(_address.text);
    return host == null ? null : NetworkConfig(kind: NetworkKind.smb, host: host, username: user, password: pass);
  }

  Future<void> _connect() async {
    final cfg = _config();
    if (cfg == null) {
      setState(() => _error = _kind == NetworkKind.smb ? '请填写 NAS 或电脑的地址' : '地址格式不对，例如 http://192.168.1.10:5005');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final probe = createProbeSource(cfg);
    final backend = RemoteBackend(probe, cfg);
    try {
      await backend.roots(); // 先验证能连上、账号正确
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);

    final picked = await FolderBrowser.pick(context, backend: backend, title: cfg.host);
    if (picked == null || !mounted) return;
    final remote = parseRemote(picked)?.$2 ?? '/';
    final name = Uri.decodeComponent(remote.split('/').where((s) => s.isNotEmpty).lastOrNull ?? cfg.host);

    final db = ref.read(dbProvider);
    final id = db.addSource(type: cfg.kind.name, name: name, root: remote, config: cfg.encode());
    ref.read(libraryRevisionProvider.notifier).bump();
    ref.read(scanProvider.notifier).scan(id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已添加「$name」，正在扫描…')));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final g = FormFactor.of(context).gutter;
    final pad = MediaQuery.paddingOf(context);
    final smb = _kind == NetworkKind.smb;

    return Scaffold(
      body: ListView(
        padding: EdgeInsets.fromLTRB(g, pad.top + 12, g, pad.bottom + 40),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Transform.translate(
                  offset: const Offset(-8, 0),
                  child: RoundIconButton(
                    icon: Icons.close_rounded,
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('添加网络存储', style: TypeScale.largeTitle),
                const SizedBox(height: 8),
                Text('直接播放 NAS 或电脑共享文件夹里的影片，不用先拷到平板上。',
                    style: TypeScale.callout.copyWith(color: Palette.text2)),
                const SizedBox(height: 28),
                Transform.translate(
                  offset: const Offset(-4, 0),
                  child: FilterPills<NetworkKind>(
                    items: NetworkKind.values,
                    selected: _kind,
                    label: (k) => k.label,
                    onSelect: (k) => setState(() {
                      _kind = k;
                      _error = null;
                    }),
                  ),
                ),
                const SizedBox(height: 20),
                GroupedList(
                  footer: smb
                      ? '支持 SMB 2.1 及以下。群晖、威联通、Windows 共享默认可用；若 NAS 强制开启了「SMB3 加密」，请改用 WebDAV。访客访问可不填账号。'
                      : '群晖需安装「WebDAV Server」套件，默认端口 5005（http）/ 5006（https）；威联通在「网络和文件服务 › WebDAV」开启。',
                  children: [
                    _Field(
                      label: '地址',
                      controller: _address,
                      hint: smb ? '192.168.1.10 或 nas.local' : 'http://192.168.1.10:5005',
                      keyboardType: TextInputType.url,
                      autofocus: true,
                    ),
                    _Field(label: '用户名', controller: _user, hint: smb ? '访客可留空' : '可选'),
                    _Field(label: '密码', controller: _pass, hint: '可选', obscure: true, onSubmitted: (_) => _connect()),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.error_outline_rounded, size: 18, color: Palette.danger),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!, style: TypeScale.callout.copyWith(color: Palette.danger))),
                  ]),
                ],
                const SizedBox(height: 28),
                Row(children: [
                  PillButton(
                    label: _busy ? '正在连接…' : '连接并选择文件夹',
                    icon: _busy ? null : Icons.arrow_forward_rounded,
                    onPressed: _busy ? null : _connect,
                  ),
                  if (_busy) ...[const SizedBox(width: 16), const Spinner()],
                ]),
                const SizedBox(height: 14),
                Text('账号密码只保存在这台设备的 App 数据里。',
                    style: TypeScale.caption.copyWith(color: Palette.text3)),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.keyboardType,
    this.autofocus = false,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 56,
        child: Row(children: [
          const SizedBox(width: 16),
          SizedBox(width: 72, child: Text(label, style: TypeScale.callout.copyWith(fontSize: 15))),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscure,
              keyboardType: keyboardType,
              autofocus: autofocus,
              autocorrect: false,
              enableSuggestions: !obscure,
              onSubmitted: onSubmitted,
              cursorColor: Palette.light,
              style: TypeScale.callout.copyWith(fontSize: 15),
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
          const SizedBox(width: 16),
        ]),
      );
}

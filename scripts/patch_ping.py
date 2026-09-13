from pathlib import Path

path = Path("lib/main.dart")
text = path.read_text()

field_anchor = "  bool _loadingServers = false;\n"
field_insert = """  final Map<String, int> _serverPings = <String, int>{};\n  final Set<String> _pingingServers = <String>{};\n  bool _pingingAll = false;\n"""
if field_insert.strip() not in text:
    if field_anchor not in text:
        raise SystemExit("ping field anchor not found")
    text = text.replace(field_anchor, field_anchor + field_insert, 1)

method_anchor = "  Future<void> _selectProfile(Profile profile) async {"
method_insert = r'''  Future<int?> _measureServerLatency(Outbound server) async {
    final profile = _selectedProfile;
    if (profile == null) return null;

    try {
      final file = File(profile.typed.path);
      if (!await file.exists()) return null;
      final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final outbounds = raw['outbounds'];
      if (outbounds is! List) return null;

      Map<String, dynamic>? target;
      for (final item in outbounds) {
        if (item is Map<String, dynamic> && item['tag']?.toString() == server.tag) {
          target = item;
          break;
        }
      }
      if (target == null) return null;

      final host = target['server']?.toString();
      final rawPort = target['server_port'];
      final port = rawPort is int ? rawPort : int.tryParse(rawPort?.toString() ?? '');
      if (host == null || host.isEmpty || port == null || port <= 0 || port > 65535) {
        return null;
      }

      final watch = Stopwatch()..start();
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 4),
      );
      watch.stop();
      socket.destroy();
      return watch.elapsedMilliseconds;
    } catch (_) {
      return null;
    }
  }

  Future<void> _pingServer(Outbound server, {bool silent = false}) async {
    if (_pingingServers.contains(server.tag)) return;
    if (mounted) {
      setState(() => _pingingServers.add(server.tag));
    }

    final latency = await _measureServerLatency(server);
    if (!mounted) return;
    setState(() {
      _pingingServers.remove(server.tag);
      _serverPings[server.tag] = latency ?? -1;
    });

    if (!silent) {
      if (latency == null) {
        _showError('پینگ «${server.tag}» ناموفق بود.');
      } else {
        _showMessage('پینگ «${server.tag}»: $latency ms');
      }
    }
  }

  Future<void> _pingAllServers() async {
    if (_pingingAll || _servers.isEmpty) return;
    setState(() {
      _pingingAll = true;
      _serverPings.clear();
    });
    try {
      for (final server in List<Outbound>.from(_servers)) {
        await _pingServer(server, silent: true);
      }
    } finally {
      if (mounted) setState(() => _pingingAll = false);
    }
  }

'''
if "Future<int?> _measureServerLatency" not in text:
    if method_anchor not in text:
        raise SystemExit("ping method anchor not found")
    text = text.replace(method_anchor, method_insert + method_anchor, 1)

old_call = '''        onRefresh: _refreshProfile,
        onDelete: _deleteProfile,
      ),'''
new_call = '''        onRefresh: _refreshProfile,
        onDelete: _deleteProfile,
        pings: _serverPings,
        pingingServers: _pingingServers,
        pingingAll: _pingingAll,
        onPing: _pingServer,
        onPingAll: _pingAllServers,
      ),'''
if old_call in text and "pings: _serverPings" not in text:
    text = text.replace(old_call, new_call, 1)

old_ctor = '''    required this.onRefresh,
    required this.onDelete,
  });'''
new_ctor = '''    required this.onRefresh,
    required this.onDelete,
    required this.pings,
    required this.pingingServers,
    required this.pingingAll,
    required this.onPing,
    required this.onPingAll,
  });'''
if old_ctor in text and "required this.pings" not in text:
    text = text.replace(old_ctor, new_ctor, 1)

old_fields = '''  final ValueChanged<Profile> onRefresh;
  final ValueChanged<Profile> onDelete;

  @override'''
new_fields = '''  final ValueChanged<Profile> onRefresh;
  final ValueChanged<Profile> onDelete;
  final Map<String, int> pings;
  final Set<String> pingingServers;
  final bool pingingAll;
  final Future<void> Function(Outbound server) onPing;
  final Future<void> Function() onPingAll;

  String pingText(Outbound server) {
    if (pingingServers.contains(server.tag)) return 'در حال تست…';
    if (!pings.containsKey(server.tag)) return 'تست نشده';
    final value = pings[server.tag]!;
    return value < 0 ? 'Timeout' : '$value ms';
  }

  @override'''
if old_fields in text and "String pingText(Outbound server)" not in text:
    text = text.replace(old_fields, new_fields, 1)

heading_anchor = '''        const SizedBox(height: 18),
        if (profiles.isEmpty)'''
heading_insert = '''        const SizedBox(height: 18),
        if (servers.isNotEmpty) ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: pingingAll ? null : onPingAll,
              icon: pingingAll
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.speed),
              label: Text(pingingAll ? 'در حال تست پینگ همه سرورها…' : 'تست پینگ همه سرورها'),
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (profiles.isEmpty)'''
if heading_anchor in text and "تست پینگ همه سرورها" not in text:
    text = text.replace(heading_anchor, heading_insert, 1)

old_tile = '''                  title: Text(server.tag, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(server.type),
                  trailing: selectedServerTag == server.tag
                      ? const Chip(label: Text('انتخاب‌شده'))
                      : const Icon(Icons.chevron_left),'''
new_tile = '''                  title: Text(server.tag, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${server.type} • ${pingText(server)}'),
                  trailing: pingingServers.contains(server.tag)
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      : IconButton(
                          tooltip: 'تست پینگ',
                          onPressed: () => onPing(server),
                          icon: const Icon(Icons.speed),
                        ),'''
if old_tile in text and "subtitle: Text('${server.type} • ${pingText(server)}')" not in text:
    text = text.replace(old_tile, new_tile, 1)

# The ping is TCP connect latency to the actual proxy endpoint. It is more
# useful than ICMP on Android because many proxy servers/firewalls drop ICMP.
# Keep the displayed version in sync with this feature build.
text = text.replace("نسخه ۱.۱.۳", "نسخه ۱.۱.۴")
text = text.replace("نسخه ۱.۱.۲", "نسخه ۱.۱.۴")

path.write_text(text)
print("Patched lib/main.dart with per-server TCP latency tests")

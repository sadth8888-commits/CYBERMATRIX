import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_sing_box/flutter_sing_box.dart';
import 'package:mmkv/mmkv.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MMKV.initialize();
  await FlutterSingBox().init();
  runApp(const CyberMatrixApp());
}

class CyberMatrixApp extends StatelessWidget {
  const CyberMatrixApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF7357FF),
      brightness: Brightness.dark,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'سایبرماتریکس تونل',
      locale: const Locale('fa'),
      supportedLocales: const [Locale('fa')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFF070B14),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF0E1422),
          indicatorColor: scheme.primary.withValues(alpha: .18),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF101827),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final FlutterSingBox _core = FlutterSingBox();
  int _page = 0;
  ProxyState _proxyState = ProxyState.stopped;
  Profile? _selectedProfile;
  List<Profile> _profiles = [];
  List<Outbound> _servers = [];
  String? _selectorGroupTag;
  String? _selectedServerTag;
  StreamSubscription<ProxyState>? _stateSub;
  StreamSubscription<List<ClientLog>>? _logSub;
  final List<String> _logs = [];
  String? _coreVersion;
  bool _loadingServers = false;

  @override
  void initState() {
    super.initState();
    unawaited(_reloadProfilesAndServers());
    _stateSub = _core.proxyStateStream.listen((state) {
      if (!mounted) return;
      setState(() => _proxyState = state);
      if (state == ProxyState.started) {
        unawaited(_applySelectedOutbound(silent: true));
      }
    });
    _logSub = _core.logStream.listen((items) {
      if (items.isEmpty || !mounted) return;
      setState(() {
        for (final item in items) {
          _logs.add(item.toString());
        }
        if (_logs.length > 120) {
          _logs.removeRange(0, _logs.length - 120);
        }
      });
    });
    unawaited(_readCoreVersion());
  }

  Future<void> _readCoreVersion() async {
    try {
      final version = await _core.getSingBoxVersion();
      if (mounted) setState(() => _coreVersion = version);
    } catch (_) {}
  }

  Future<void> _reloadProfilesAndServers() async {
    final profiles = ProfileStorage().getProfiles();
    final selected = ProfileStorage().getSelectedProfile();
    if (mounted) {
      setState(() {
        _profiles = profiles;
        _selectedProfile = selected;
      });
    }
    await _loadServers(selected);
  }

  Future<void> _loadServers(Profile? profile) async {
    if (mounted) {
      setState(() {
        _loadingServers = true;
        _servers = [];
        _selectorGroupTag = null;
        _selectedServerTag = null;
      });
    }
    if (profile == null) {
      if (mounted) setState(() => _loadingServers = false);
      return;
    }

    try {
      final file = File(profile.typed.path);
      if (!await file.exists()) {
        throw Exception('فایل کانفیگ پیدا نشد');
      }
      final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final singBox = SingBox.fromJson(raw);

      Outbound? selector;
      for (final outbound in singBox.outbounds) {
        if (outbound.type == OutboundType.selector &&
            outbound.outbounds?.isNotEmpty == true) {
          selector = outbound;
          break;
        }
      }

      if (selector == null) {
        throw Exception('گروه انتخاب سرور در این اشتراک پیدا نشد');
      }

      final tags = selector.outbounds ?? const <String>[];
      final servers = <Outbound>[];
      for (final tag in tags) {
        for (final outbound in singBox.outbounds) {
          if (outbound.tag == tag) {
            servers.add(outbound);
            break;
          }
        }
      }

      final key = _serverStorageKey(profile.id);
      var selectedTag = ProfileStorage.storage.getString(key);
      if (selectedTag == null || !servers.any((e) => e.tag == selectedTag)) {
        selectedTag = servers.isEmpty ? null : servers.first.tag;
        if (selectedTag != null) {
          ProfileStorage.storage.setString(key, selectedTag);
        }
      }

      if (!mounted) return;
      setState(() {
        _servers = servers;
        _selectorGroupTag = selector!.tag;
        _selectedServerTag = selectedTag;
        _loadingServers = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingServers = false);
      _showError('خواندن سرورها ناموفق بود: $e');
    }
  }

  String _serverStorageKey(int profileId) => 'cm_selected_server_$profileId';

  Future<void> _selectProfile(Profile profile) async {
    final wasRunning = _proxyState == ProxyState.started ||
        _proxyState == ProxyState.starting;
    try {
      if (wasRunning) await _core.stopVpn();
      ProfileStorage().setSelectedProfile(profile.id);
      await _reloadProfilesAndServers();
      if (wasRunning) {
        await _core.startVpn();
      }
    } catch (e) {
      _showError('تغییر اشتراک انجام نشد: $e');
    }
  }

  Future<void> _selectServer(Outbound server) async {
    final profile = _selectedProfile;
    if (profile == null) return;

    ProfileStorage.storage.setString(_serverStorageKey(profile.id), server.tag);
    if (mounted) setState(() => _selectedServerTag = server.tag);

    if (_proxyState == ProxyState.started) {
      try {
        await _applySelectedOutbound();
      } catch (_) {}
    } else {
      _showMessage('سرور «${server.tag}» انتخاب شد و هنگام اتصال استفاده می‌شود.');
    }
  }

  Future<void> _applySelectedOutbound({bool silent = false}) async {
    final group = _selectorGroupTag;
    final server = _selectedServerTag;
    if (group == null || server == null || _proxyState != ProxyState.started) {
      return;
    }
    try {
      await _core.selectOutbound(groupTag: group, outboundTag: server);
      if (!silent) _showMessage('سرور «$server» فعال شد.');
    } catch (e) {
      if (!silent) _showError('انتخاب سرور ناموفق بود: $e');
    }
  }

  Future<void> _toggleVpn() async {
    if (_proxyState == ProxyState.starting ||
        _proxyState == ProxyState.stopping) {
      return;
    }
    if (_proxyState == ProxyState.started) {
      try {
        await _core.stopVpn();
      } catch (e) {
        _showError('قطع اتصال ناموفق بود: $e');
      }
      return;
    }
    if (_selectedProfile == null) {
      _showError('اول یک اشتراک وارد و انتخاب کن.');
      setState(() => _page = 2);
      return;
    }
    if (_selectedServerTag == null) {
      _showError('اول یک سرور انتخاب کن.');
      setState(() => _page = 1);
      return;
    }
    try {
      await Permission.notification.request();
      await _core.startVpn();
    } on PlatformException catch (e) {
      if (e.code == 'VPN_PERMISSION_DENIED') {
        _showError('اجازه VPN توسط کاربر رد شد.');
      } else {
        _showError(e.message ?? 'راه‌اندازی VPN ناموفق بود.');
      }
    } catch (e) {
      _showError('راه‌اندازی VPN ناموفق بود: $e');
    }
  }

  Future<void> _importSubscription(String title, String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
      _showError('لینک اشتراک معتبر نیست. QR باید شامل لینک http یا https باشد.');
      return;
    }
    try {
      final profile = await ProfileService().importProfile(
        subscribeLink: uri,
        name: title.trim().isEmpty ? null : title.trim(),
        userAgent: 'CyberMatrixTunnel/1.1',
      );
      ProfileStorage().setSelectedProfile(profile.id);
      await _reloadProfilesAndServers();
      _showMessage('اشتراک با ${profile.outboundsCount} سرور وارد شد.');
      if (mounted) setState(() => _page = 1);
    } catch (e) {
      _showError('وارد کردن اشتراک ناموفق بود: $e');
    }
  }

  Future<void> _refreshProfile(Profile profile) async {
    try {
      await ProfileService().importProfile(id: profile.id);
      await _reloadProfilesAndServers();
      _showMessage('اشتراک بروزرسانی شد.');
    } catch (e) {
      _showError('بروزرسانی ناموفق بود: $e');
    }
  }

  Future<void> _deleteProfile(Profile profile) async {
    final wasSelected = _selectedProfile?.id == profile.id;
    if (wasSelected && _proxyState == ProxyState.started) {
      await _core.stopVpn();
    }
    ProfileStorage().deleteProfile(profile.id);
    await _reloadProfilesAndServers();
  }

  void _showError(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: Colors.red.shade800),
    );
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomePage(
        state: _proxyState,
        profile: _selectedProfile,
        selectedServerTag: _selectedServerTag,
        coreVersion: _coreVersion,
        onToggle: _toggleVpn,
        onOpenServers: () => setState(() => _page = 1),
      ),
      ServersPage(
        profiles: _profiles,
        selectedProfile: _selectedProfile,
        servers: _servers,
        selectedServerTag: _selectedServerTag,
        loading: _loadingServers,
        onProfileChanged: _selectProfile,
        onServerSelected: _selectServer,
        onRefresh: _refreshProfile,
        onDelete: _deleteProfile,
      ),
      SubscriptionPage(onImport: _importSubscription),
      LogsPage(logs: _logs),
      const SettingsPage(),
    ];

    return Scaffold(
      body: SafeArea(child: pages[_page]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _page,
        onDestinationSelected: (value) => setState(() => _page = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.shield_outlined), label: 'خانه'),
          NavigationDestination(icon: Icon(Icons.dns_outlined), label: 'سرورها'),
          NavigationDestination(icon: Icon(Icons.qr_code_scanner), label: 'اشتراک'),
          NavigationDestination(icon: Icon(Icons.terminal), label: 'لاگ'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'تنظیمات'),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _logSub?.cancel();
    super.dispose();
  }
}

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.state,
    required this.profile,
    required this.selectedServerTag,
    required this.coreVersion,
    required this.onToggle,
    required this.onOpenServers,
  });

  final ProxyState state;
  final Profile? profile;
  final String? selectedServerTag;
  final String? coreVersion;
  final VoidCallback onToggle;
  final VoidCallback onOpenServers;

  bool get connected => state == ProxyState.started;
  bool get busy => state == ProxyState.starting || state == ProxyState.stopping;

  String get statusText => switch (state) {
        ProxyState.started => 'متصل',
        ProxyState.starting => 'در حال اتصال…',
        ProxyState.stopping => 'در حال قطع…',
        ProxyState.unknown => 'نامشخص',
        _ => 'قطع',
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                gradient: LinearGradient(colors: [scheme.primary, scheme.tertiary]),
              ),
              child: const Icon(Icons.security, color: Colors.white),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('سایبرماتریکس تونل', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  Text('اتصال امن با sing-box', style: TextStyle(color: Colors.white54)),
                ],
              ),
            ),
            Chip(label: Text(statusText)),
          ],
        ),
        const SizedBox(height: 36),
        Center(
          child: GestureDetector(
            onTap: busy ? null : onToggle,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: connected
                      ? [scheme.primary, scheme.tertiary]
                      : [const Color(0xFF1A2234), const Color(0xFF0F1522)],
                ),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 50,
                    color: scheme.primary.withValues(alpha: connected ? .35 : .08),
                  ),
                ],
              ),
              child: busy
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.power_settings_new, size: 60),
                        const SizedBox(height: 10),
                        Text(connected ? 'قطع اتصال' : 'اتصال', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                      ],
                    ),
            ),
          ),
        ),
        const SizedBox(height: 28),
        Panel(
          child: ListTile(
            onTap: onOpenServers,
            leading: const Icon(Icons.public),
            title: Text(selectedServerTag ?? 'هیچ سروری انتخاب نشده'),
            subtitle: Text(profile == null
                ? 'از بخش اشتراک، لینک سرویس خودت را وارد کن'
                : '${profile!.name} • ${profile!.outboundsCount} سرور'),
            trailing: const Icon(Icons.chevron_left),
          ),
        ),
        const SizedBox(height: 12),
        Panel(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('هسته اتصال', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text('sing-box ${coreVersion ?? 'در حال شناسایی…'}', style: const TextStyle(color: Colors.white60)),
                const SizedBox(height: 4),
                const Text('سرور انتخابی هنگام اتصال روی گروه Selector اعمال می‌شود.', style: TextStyle(color: Colors.white60, height: 1.5)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class ServersPage extends StatelessWidget {
  const ServersPage({
    super.key,
    required this.profiles,
    required this.selectedProfile,
    required this.servers,
    required this.selectedServerTag,
    required this.loading,
    required this.onProfileChanged,
    required this.onServerSelected,
    required this.onRefresh,
    required this.onDelete,
  });

  final List<Profile> profiles;
  final Profile? selectedProfile;
  final List<Outbound> servers;
  final String? selectedServerTag;
  final bool loading;
  final ValueChanged<Profile> onProfileChanged;
  final ValueChanged<Outbound> onServerSelected;
  final ValueChanged<Profile> onRefresh;
  final ValueChanged<Profile> onDelete;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('سرورها', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text('هر سرور اشتراک جدا نمایش داده می‌شود و می‌توانی یکی را برای اتصال انتخاب کنی.', style: TextStyle(color: Colors.white60, height: 1.5)),
        const SizedBox(height: 18),
        if (profiles.isEmpty)
          const Panel(child: Padding(padding: EdgeInsets.all(20), child: Text('هنوز اشتراکی وارد نشده است.')))
        else ...[
          Panel(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.layers_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<Profile>(
                        isExpanded: true,
                        value: selectedProfile,
                        items: profiles
                            .map((p) => DropdownMenuItem(value: p, child: Text(p.name, overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (p) {
                          if (p != null) onProfileChanged(p);
                        },
                      ),
                    ),
                  ),
                  if (selectedProfile != null)
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'refresh') onRefresh(selectedProfile!);
                        if (value == 'delete') onDelete(selectedProfile!);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'refresh', child: Text('بروزرسانی اشتراک')),
                        PopupMenuItem(value: 'delete', child: Text('حذف اشتراک')),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (loading)
            const Center(child: Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()))
          else if (servers.isEmpty)
            const Panel(child: Padding(padding: EdgeInsets.all(20), child: Text('سروری در این اشتراک پیدا نشد.')))
          else
            for (final server in servers) ...[
              Panel(
                child: ListTile(
                  onTap: () => onServerSelected(server),
                  leading: Icon(
                    selectedServerTag == server.tag ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  ),
                  title: Text(server.tag, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(server.type),
                  trailing: selectedServerTag == server.tag
                      ? const Chip(label: Text('انتخاب‌شده'))
                      : const Icon(Icons.chevron_left),
                ),
              ),
              const SizedBox(height: 10),
            ],
        ],
      ],
    );
  }
}

class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key, required this.onImport});
  final Future<void> Function(String title, String url) onImport;

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  final _title = TextEditingController();
  final _url = TextEditingController();
  bool _loading = false;

  Future<void> _submit() async {
    if (_url.text.trim().isEmpty) return;
    setState(() => _loading = true);
    await widget.onImport(_title.text, _url.text);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _scanQr() async {
    final value = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScannerPage()),
    );
    if (!mounted || value == null || value.trim().isEmpty) return;
    _url.text = value.trim();
    await _submit();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('افزودن اشتراک', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text(
          'لینک Subscription را دستی وارد کن یا QR کد اشتراک را اسکن کن. بعد از Import، سرورها به‌صورت جدا در بخش «سرورها» نمایش داده می‌شوند.',
          style: TextStyle(color: Colors.white60, height: 1.5),
        ),
        const SizedBox(height: 20),
        TextField(controller: _title, decoration: const InputDecoration(labelText: 'نام دلخواه (اختیاری)')),
        const SizedBox(height: 12),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(labelText: 'Subscription URL', hintText: 'https://example.com/sub/...'),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _loading ? null : _submit,
          icon: _loading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.download),
          label: const Text('دریافت و افزودن اشتراک'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _loading ? null : _scanQr,
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('اسکن QR اشتراک'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _url.dispose();
    super.dispose();
  }
}

class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _finished = false;

  void _onDetect(BarcodeCapture capture) {
    if (_finished) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      if (value == null || value.isEmpty) continue;
      _finished = true;
      unawaited(_controller.stop());
      Navigator.of(context).pop(value);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('اسکن QR'),
        actions: [
          IconButton(
            tooltip: 'فلش',
            onPressed: _controller.toggleTorch,
            icon: const Icon(Icons.flash_on),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white, width: 3),
                ),
              ),
            ),
          ),
          const Positioned(
            left: 24,
            right: 24,
            bottom: 36,
            child: Text(
              'QR کد اشتراک را داخل کادر قرار بده',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, shadows: [Shadow(blurRadius: 8, color: Colors.black)]),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class LogsPage extends StatelessWidget {
  const LogsPage({super.key, required this.logs});
  final List<String> logs;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('لاگ اتصال', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          Expanded(
            child: Panel(
              child: logs.isEmpty
                  ? const Center(child: Text('هنوز لاگی دریافت نشده است.'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(14),
                      reverse: true,
                      itemCount: logs.length,
                      itemBuilder: (_, index) => Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: SelectableText(
                          logs[logs.length - 1 - index],
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: const [
        Text('تنظیمات و درباره', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        SizedBox(height: 18),
        Panel(
          child: Column(
            children: [
              ListTile(leading: Icon(Icons.language), title: Text('زبان'), subtitle: Text('فارسی • راست‌به‌چپ')),
              Divider(height: 1),
              ListTile(leading: Icon(Icons.person_outline), title: Text('توسعه‌دهنده'), subtitle: Text('مصطفی صادقی')),
              Divider(height: 1),
              ListTile(leading: Icon(Icons.info_outline), title: Text('نسخه'), subtitle: Text('۱.۱.۰')),
              Divider(height: 1),
              ListTile(leading: Icon(Icons.security), title: Text('موتور VPN'), subtitle: Text('sing-box + Android VPNService')),
              Divider(height: 1),
              ListTile(leading: Icon(Icons.qr_code_scanner), title: Text('QR Scanner'), subtitle: Text('Mobile Scanner + ML Kit')),
            ],
          ),
        ),
      ],
    );
  }
}

class Panel extends StatelessWidget {
  const Panel({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0E1422),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: .06)),
      ),
      child: child,
    );
  }
}

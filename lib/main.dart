import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_sing_box/flutter_sing_box.dart';
import 'package:mmkv/mmkv.dart';
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
  StreamSubscription<ProxyState>? _stateSub;
  StreamSubscription<List<ClientLog>>? _logSub;
  final List<String> _logs = [];
  String? _coreVersion;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
    _stateSub = _core.proxyStateStream.listen((state) {
      if (mounted) setState(() => _proxyState = state);
    });
    _logSub = _core.logStream.listen((items) {
      if (items.isEmpty || !mounted) return;
      setState(() {
        for (final item in items) {
          _logs.add(item.toString());
        }
        if (_logs.length > 100) {
          _logs.removeRange(0, _logs.length - 100);
        }
      });
    });
    _readCoreVersion();
  }

  Future<void> _readCoreVersion() async {
    try {
      final version = await _core.getSingBoxVersion();
      if (mounted) setState(() => _coreVersion = version);
    } catch (_) {}
  }

  void _loadProfiles() {
    setState(() {
      _profiles = ProfileStorage().getProfiles();
      _selectedProfile = ProfileStorage().getSelectedProfile();
    });
  }

  Future<void> _selectProfile(Profile profile) async {
    final wasRunning = _proxyState == ProxyState.started ||
        _proxyState == ProxyState.starting;
    try {
      if (wasRunning) await _core.stopVpn();
      ProfileStorage().setSelectedProfile(profile.id);
      _loadProfiles();
      if (wasRunning) await _core.startVpn();
    } catch (e) {
      _showError('تغییر پروفایل انجام نشد: $e');
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
      _showError('لینک اشتراک معتبر نیست.');
      return;
    }
    try {
      final profile = await ProfileService().importProfile(
        subscribeLink: uri,
        name: title.trim().isEmpty ? null : title.trim(),
        userAgent: 'CyberMatrixTunnel/1.0',
      );
      ProfileStorage().setSelectedProfile(profile.id);
      _loadProfiles();
      _showMessage('اشتراک با ${profile.outboundsCount} سرور وارد شد.');
    } catch (e) {
      _showError('وارد کردن اشتراک ناموفق بود: $e');
    }
  }

  Future<void> _refreshProfile(Profile profile) async {
    try {
      await ProfileService().importProfile(id: profile.id);
      _loadProfiles();
      _showMessage('اشتراک بروزرسانی شد.');
    } catch (e) {
      _showError('بروزرسانی ناموفق بود: $e');
    }
  }

  void _deleteProfile(Profile profile) {
    final wasSelected = _selectedProfile?.id == profile.id;
    ProfileStorage().deleteProfile(profile.id);
    _loadProfiles();
    if (wasSelected && _proxyState == ProxyState.started) {
      _core.stopVpn();
    }
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
        coreVersion: _coreVersion,
        onToggle: _toggleVpn,
        onOpenProfiles: () => setState(() => _page = 1),
      ),
      ProfilesPage(
        profiles: _profiles,
        selected: _selectedProfile,
        onSelect: _selectProfile,
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
          NavigationDestination(icon: Icon(Icons.dns_outlined), label: 'پروفایل‌ها'),
          NavigationDestination(icon: Icon(Icons.add_link), label: 'اشتراک'),
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
    required this.coreVersion,
    required this.onToggle,
    required this.onOpenProfiles,
  });

  final ProxyState state;
  final Profile? profile;
  final String? coreVersion;
  final VoidCallback onToggle;
  final VoidCallback onOpenProfiles;

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
            onTap: onOpenProfiles,
            leading: const Icon(Icons.public),
            title: Text(profile?.name ?? 'هیچ پروفایلی انتخاب نشده'),
            subtitle: Text(profile == null
                ? 'از بخش اشتراک، لینک سرویس خودت را وارد کن'
                : '${profile!.outboundsCount} سرور • آخرین بروزرسانی ${formatDate(profile!.typed.lastUpdated)}'),
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
                const Text('VPNService اندروید فعال است و دکمه اتصال به سرویس واقعی متصل شده.', style: TextStyle(color: Colors.white60, height: 1.5)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class ProfilesPage extends StatelessWidget {
  const ProfilesPage({
    super.key,
    required this.profiles,
    required this.selected,
    required this.onSelect,
    required this.onRefresh,
    required this.onDelete,
  });

  final List<Profile> profiles;
  final Profile? selected;
  final ValueChanged<Profile> onSelect;
  final ValueChanged<Profile> onRefresh;
  final ValueChanged<Profile> onDelete;

  @override
  Widget build(BuildContext context) {
    if (profiles.isEmpty) {
      return const Center(child: Text('هنوز اشتراکی وارد نشده است.'));
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('پروفایل‌ها', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        const SizedBox(height: 18),
        for (final profile in profiles) ...[
          Panel(
            child: ListTile(
              onTap: () => onSelect(profile),
              leading: Icon(
                selected?.id == profile.id ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              ),
              title: Text(profile.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${profile.outboundsCount} سرور • ${formatDate(profile.typed.lastUpdated)}'),
              trailing: PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'refresh') onRefresh(profile);
                  if (value == 'delete') onDelete(profile);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'refresh', child: Text('بروزرسانی')),
                  PopupMenuItem(value: 'delete', child: Text('حذف')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
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

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('افزودن اشتراک', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text(
          'لینک Subscription خودت را وارد کن. فرمت‌های Base64، Clash YAML و sing-box JSON توسط هسته تبدیل می‌شوند.',
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
              ListTile(leading: Icon(Icons.info_outline), title: Text('نسخه'), subtitle: Text('۱.۰.۰')),
              Divider(height: 1),
              ListTile(leading: Icon(Icons.security), title: Text('موتور VPN'), subtitle: Text('sing-box + Android VPNService')),
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

String formatDate(int millis) {
  final d = DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
  return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
}

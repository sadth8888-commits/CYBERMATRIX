from pathlib import Path

path = Path("lib/main.dart")
text = path.read_text()

anchor = "  String _serverStorageKey(int profileId) => 'cm_selected_server_$profileId';\n"
insert = r'''

  Future<File> _prepareUsingConfig() async {
    final profile = _selectedProfile;
    if (profile == null) {
      throw Exception('هیچ اشتراکی انتخاب نشده است');
    }

    final source = File(profile.typed.path);
    if (!await source.exists()) {
      throw Exception('فایل کانفیگ اشتراک پیدا نشد');
    }

    final raw = jsonDecode(await source.readAsString()) as Map<String, dynamic>;

    // Make the UI-selected server the selector default before the native
    // :remote VPN process reads this config.
    final group = _selectorGroupTag;
    final server = _selectedServerTag;
    final outbounds = raw['outbounds'];
    if (group != null && server != null && outbounds is List) {
      for (final item in outbounds) {
        if (item is Map<String, dynamic> && item['tag'] == group) {
          item['default'] = server;
          break;
        }
      }
    }

    // flutter_sing_box's Android service does NOT read profile.typed.path.
    // It reads <using_config>/using_config.json from the shared MMKV key.
    // Keep that file synchronized before every start/restart.
    final dir = await ProfileStorage().getStorageDirectory();
    await dir.create(recursive: true);
    ProfileStorage().setUsingConfig(dir.path);
    final usingConfig = File('${dir.path}/using_config.json');
    await usingConfig.writeAsString(jsonEncode(raw), flush: true);

    // Validate once in Dart before handing it to the native service.
    SingBox.fromJson(raw);

    if (mounted) {
      setState(() {
        _logs.add('CyberMatrix: using_config آماده شد: ${usingConfig.path}');
        if (_logs.length > 120) {
          _logs.removeRange(0, _logs.length - 120);
        }
      });
    }
    return usingConfig;
  }
'''
if "Future<File> _prepareUsingConfig()" not in text:
    if anchor not in text:
        raise SystemExit("serverStorageKey anchor not found")
    text = text.replace(anchor, anchor + insert, 1)

start = text.index("  Future<void> _toggleVpn() async {")
end = text.index("  Future<void> _importSubscription", start)
new_toggle = r'''  Future<void> _toggleVpn() async {
    if (_proxyState == ProxyState.starting ||
        _proxyState == ProxyState.stopping) {
      return;
    }

    if (_proxyState == ProxyState.started) {
      try {
        if (mounted) setState(() => _proxyState = ProxyState.stopping);
        await _core.stopVpn();
      } catch (e) {
        if (mounted) setState(() => _proxyState = ProxyState.stopped);
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
      // Show feedback immediately even before the native state stream emits.
      if (mounted) setState(() => _proxyState = ProxyState.starting);
      _showMessage('در حال آماده‌سازی ${_selectedServerTag!}…');

      await _prepareUsingConfig();

      // Notification permission is helpful on Android 13+, but a denial must
      // not prevent the VPN permission dialog/service startup.
      try {
        await Permission.notification.request();
      } catch (_) {}

      await _core.startVpn();

      // The native service starts asynchronously. If no started event arrives,
      // return the UI to stopped and point the user to the real core logs.
      await Future.delayed(const Duration(seconds: 8));
      if (mounted && _proxyState == ProxyState.starting) {
        setState(() => _proxyState = ProxyState.stopped);
        _showError('سرویس VPN شروع نشد. بخش «لاگ» را بررسی کن.');
      }
    } on PlatformException catch (e) {
      if (mounted) setState(() => _proxyState = ProxyState.stopped);
      if (e.code == 'VPN_PERMISSION_DENIED') {
        _showError('اجازه VPN توسط کاربر رد شد.');
      } else if (e.code == 'NO_ACTIVITY') {
        _showError('Activity اندروید در دسترس نیست. برنامه را یک‌بار ببند و دوباره باز کن.');
      } else {
        _showError(e.message ?? 'راه‌اندازی VPN ناموفق بود.');
      }
    } catch (e) {
      if (mounted) setState(() => _proxyState = ProxyState.stopped);
      _showError('راه‌اندازی VPN ناموفق بود: $e');
    }
  }

'''
text = text[:start] + new_toggle + text[end:]

old_restart = """      if (wasRunning) {\n        await _core.startVpn();\n      }"""
new_restart = """      if (wasRunning) {\n        await _prepareUsingConfig();\n        if (mounted) setState(() => _proxyState = ProxyState.starting);\n        await _core.startVpn();\n      }"""
text = text.replace(old_restart, new_restart, 1)

# Keep the runtime config synchronized when a server is selected while stopped.
old_select_else = """    } else {\n      _showMessage('سرور «${server.tag}» انتخاب شد و هنگام اتصال استفاده می‌شود.');\n    }"""
new_select_else = """    } else {\n      try {\n        await _prepareUsingConfig();\n      } catch (_) {}\n      _showMessage('سرور «${server.tag}» انتخاب شد و هنگام اتصال استفاده می‌شود.');\n    }"""
text = text.replace(old_select_else, new_select_else, 1)

# Version label for this runtime fix.
text = text.replace("subtitle: Text('۱.۱.۰')", "subtitle: Text('۱.۱.۱')")

path.write_text(text)
print("Patched lib/main.dart for native using_config handoff")

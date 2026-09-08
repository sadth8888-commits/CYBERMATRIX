from pathlib import Path

path = Path("lib/main.dart")
text = path.read_text()

# Native bridge used to hand the final JSON to the Android process with native
# MMKV + app-private storage. This avoids relying only on Dart MMKV visibility
# across the :remote VPN process.
core_anchor = "  final FlutterSingBox _core = FlutterSingBox();\n"
core_insert = "  static const MethodChannel _nativeVpnChannel = MethodChannel('flutter_sing_box_method');\n"
if core_insert not in text:
    if core_anchor not in text:
        raise SystemExit("core anchor not found")
    text = text.replace(core_anchor, core_anchor + core_insert, 1)

# Track a user initiated connection attempt so an asynchronous native service
# failure cannot silently snap the UI back to Stopped.
field_anchor = "  bool _loadingServers = false;\n"
field_insert = "  bool _connectAttemptActive = false;\n"
if field_insert not in text:
    if field_anchor not in text:
        raise SystemExit("loadingServers anchor not found")
    text = text.replace(field_anchor, field_anchor + field_insert, 1)

# Replace the proxy-state listener with one that surfaces early native failures.
old_state_listener = '''    _stateSub = _core.proxyStateStream.listen((state) {
      if (!mounted) return;
      setState(() => _proxyState = state);
      if (state == ProxyState.started) {
        unawaited(_applySelectedOutbound(silent: true));
      }
    });
'''
new_state_listener = '''    _stateSub = _core.proxyStateStream.listen((state) {
      if (!mounted) return;
      final failedDuringStart = state == ProxyState.stopped && _connectAttemptActive;
      setState(() {
        _proxyState = state;
        if (state == ProxyState.started || failedDuringStart) {
          _connectAttemptActive = false;
        }
      });
      if (state == ProxyState.started) {
        unawaited(_applySelectedOutbound(silent: true));
        _showMessage('VPN با موفقیت متصل شد.');
      } else if (failedDuringStart) {
        _showError('سرویس VPN قبل از اتصال متوقف شد. خطای دقیق در بخش «لاگ» ثبت شده است.');
      }
    });
'''
if old_state_listener in text:
    text = text.replace(old_state_listener, new_state_listener, 1)

# ClientLog.toString() only prints "Instance of ClientLog". Store the real
# message so native service alerts and sing-box errors are visible to the user.
old_log_listener = '''    _logSub = _core.logStream.listen((items) {
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
'''
new_log_listener = '''    _logSub = _core.logStream.listen((items) {
      if (items.isEmpty || !mounted) return;
      String? serviceAlert;
      setState(() {
        for (final item in items) {
          final line = '[${item.level}] ${item.message}';
          _logs.add(line);
          if (item.message.contains('VPN_ALERT')) {
            serviceAlert = item.message;
          }
        }
        if (_logs.length > 300) {
          _logs.removeRange(0, _logs.length - 300);
        }
      });
      if (serviceAlert != null) {
        _showError(serviceAlert!.replaceFirst('VPN_ALERT: ', 'خطای VPN: '));
      }
    });
'''
if old_log_listener in text:
    text = text.replace(old_log_listener, new_log_listener, 1)

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

    // sing-box requires every outbound/endpoint tag to be globally unique.
    // Some subscriptions legally reuse display names (for example two nodes
    // named "Cloud"), but the parser rejects those names when they become tags.
    // Normalize duplicates deterministically and rewrite selector references so
    // every server remains selectable instead of simply deleting duplicates.
    int normalizedDuplicateTags = 0;
    final outboundsValue = raw['outbounds'];
    if (outboundsValue is List) {
      final usedTags = <String>{};
      final renamedByOriginal = <String, List<String>>{};

      for (final item in outboundsValue) {
        if (item is! Map<String, dynamic>) continue;
        final original = item['tag']?.toString();
        if (original == null || original.isEmpty) continue;

        var candidate = original;
        var suffix = 2;
        while (usedTags.contains(candidate)) {
          candidate = '$original · $suffix';
          suffix++;
        }
        usedTags.add(candidate);
        renamedByOriginal.putIfAbsent(original, () => <String>[]).add(candidate);
        if (candidate != original) {
          item['tag'] = candidate;
          normalizedDuplicateTags++;
        }
      }

      // Rewrite selector/urltest references occurrence-by-occurrence. This is
      // important when the provider listed the same display tag more than once.
      for (final item in outboundsValue) {
        if (item is! Map<String, dynamic>) continue;
        final refs = item['outbounds'];
        if (refs is List) {
          final occurrence = <String, int>{};
          for (var i = 0; i < refs.length; i++) {
            final original = refs[i]?.toString();
            if (original == null) continue;
            final choices = renamedByOriginal[original];
            if (choices == null || choices.isEmpty) continue;
            final index = occurrence[original] ?? 0;
            refs[i] = choices[index < choices.length ? index : choices.length - 1];
            occurrence[original] = index + 1;
          }
        }

        final defaultTag = item['default']?.toString();
        if (defaultTag != null) {
          final choices = renamedByOriginal[defaultTag];
          if (choices != null && choices.isNotEmpty) {
            item['default'] = choices.first;
          }
        }
      }

      // Endpoints share the same tag namespace with outbounds in sing-box.
      final endpointsValue = raw['endpoints'];
      if (endpointsValue is List) {
        for (final item in endpointsValue) {
          if (item is! Map<String, dynamic>) continue;
          final original = item['tag']?.toString();
          if (original == null || original.isEmpty) continue;
          var candidate = original;
          var suffix = 2;
          while (usedTags.contains(candidate)) {
            candidate = '$original · endpoint $suffix';
            suffix++;
          }
          usedTags.add(candidate);
          if (candidate != original) {
            item['tag'] = candidate;
            normalizedDuplicateTags++;
          }
        }
      }

      // Route references to a duplicated name are inherently ambiguous; using
      // the first matching normalized tag matches sing-box/provider behavior.
      String normalizeReference(String value) {
        final choices = renamedByOriginal[value];
        return choices == null || choices.isEmpty ? value : choices.first;
      }

      final route = raw['route'];
      if (route is Map<String, dynamic>) {
        final routeFinal = route['final']?.toString();
        if (routeFinal != null) route['final'] = normalizeReference(routeFinal);
        final rules = route['rules'];
        if (rules is List) {
          for (final rule in rules) {
            if (rule is! Map<String, dynamic>) continue;
            final outbound = rule['outbound']?.toString();
            if (outbound != null) rule['outbound'] = normalizeReference(outbound);
          }
        }
      }
    }

    // Persist the UI-selected server as the selector default before the native
    // service validates/starts the configuration. If that selected tag was a
    // duplicate and got renamed above, prefer the exact surviving selector ref.
    final group = _selectorGroupTag;
    final server = _selectedServerTag;
    final outbounds = raw['outbounds'];
    if (group != null && server != null && outbounds is List) {
      for (final item in outbounds) {
        if (item is Map<String, dynamic> && item['tag'] == group) {
          final refs = item['outbounds'];
          if (refs is List && refs.isNotEmpty) {
            final exact = refs.where((e) => e?.toString() == server).toList();
            item['default'] = exact.isNotEmpty ? server : refs.first.toString();
          } else {
            item['default'] = server;
          }
          break;
        }
      }
    }

    // Validate the normalized model in Dart first.
    SingBox.fromJson(raw);
    final content = jsonEncode(raw);

    // Keep the normal plugin hand-off for compatibility.
    final dir = await ProfileStorage().getStorageDirectory();
    await dir.create(recursive: true);
    ProfileStorage().setUsingConfig(dir.path);
    final usingConfig = File('${dir.path}/using_config.json');
    await usingConfig.writeAsString(content, flush: true);

    // Also hand the exact same JSON to native Android. The patched plugin
    // writes it using native MMKV in MULTI_PROCESS_MODE, which guarantees that
    // the :remote VPN process sees the path even on devices where Dart MMKV
    // propagation is delayed.
    final nativePath = await _nativeVpnChannel.invokeMethod<String>(
      'setRuntimeConfig',
      <String, dynamic>{
        'content': content,
        'profileName': profile.name,
      },
    );

    // Keep the local normalized profile in sync as a final fallback for the
    // native service. This also means the server list will use the normalized
    // unique tags the next time it is loaded.
    await source.writeAsString(content, flush: true);

    if (mounted) {
      setState(() {
        _logs.add('CyberMatrix: runtime config آماده شد: ${nativePath ?? usingConfig.path}');
        if (normalizedDuplicateTags > 0) {
          _logs.add('CyberMatrix: $normalizedDuplicateTags تگ تکراری کانفیگ به‌صورت خودکار اصلاح شد.');
        }
        if (_logs.length > 300) {
          _logs.removeRange(0, _logs.length - 300);
        }
      });
    }
    return usingConfig;
  }
'''

# Replace an older generated implementation if present, otherwise insert it.
start_marker = "  Future<File> _prepareUsingConfig() async {"
if start_marker in text:
    start = text.index(start_marker)
    end = text.index("  Future<void> _selectProfile", start)
    text = text[:start] + insert.lstrip("\n") + "\n" + text[end:]
else:
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
        if (mounted) {
          setState(() {
            _connectAttemptActive = false;
            _proxyState = ProxyState.stopping;
          });
        }
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
      if (mounted) {
        setState(() {
          _connectAttemptActive = true;
          _proxyState = ProxyState.starting;
        });
      }
      _showMessage('در حال اتصال به «${_selectedServerTag!}»…');

      await _prepareUsingConfig();

      try {
        await Permission.notification.request();
      } catch (_) {}

      await _core.startVpn();

      // Native service startup is asynchronous. Give it enough time to emit a
      // definitive Started/Stopped state. If neither arrives, surface it.
      await Future.delayed(const Duration(seconds: 12));
      if (mounted && _connectAttemptActive && _proxyState == ProxyState.starting) {
        setState(() {
          _connectAttemptActive = false;
          _proxyState = ProxyState.stopped;
          _page = 3;
        });
        _showError('پاسخی از سرویس VPN دریافت نشد. لاگ اتصال را بررسی کن.');
      }
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() {
          _connectAttemptActive = false;
          _proxyState = ProxyState.stopped;
        });
      }
      if (e.code == 'VPN_PERMISSION_DENIED') {
        _showError('اجازه VPN توسط کاربر رد شد.');
      } else if (e.code == 'NO_ACTIVITY') {
        _showError('Activity اندروید در دسترس نیست. برنامه را کامل ببند و دوباره باز کن.');
      } else {
        _showError('${e.code}: ${e.message ?? 'راه‌اندازی VPN ناموفق بود.'}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _connectAttemptActive = false;
          _proxyState = ProxyState.stopped;
        });
      }
      _showError('راه‌اندازی VPN ناموفق بود: $e');
    }
  }

'''
text = text[:start] + new_toggle + text[end:]

old_restart = """      if (wasRunning) {\n        await _core.startVpn();\n      }"""
new_restart = """      if (wasRunning) {\n        await _prepareUsingConfig();\n        if (mounted) {\n          setState(() {\n            _connectAttemptActive = true;\n            _proxyState = ProxyState.starting;\n          });\n        }\n        await _core.startVpn();\n      }"""
text = text.replace(old_restart, new_restart, 1)

old_select_else = """    } else {\n      _showMessage('سرور «${server.tag}» انتخاب شد و هنگام اتصال استفاده می‌شود.');\n    }"""
new_select_else = """    } else {\n      try {\n        await _prepareUsingConfig();\n      } catch (_) {}\n      _showMessage('سرور «${server.tag}» انتخاب شد و هنگام اتصال استفاده می‌شود.');\n    }"""
text = text.replace(old_select_else, new_select_else, 1)

text = text.replace("subtitle: Text('۱.۱.۰')", "subtitle: Text('۱.۱.۳')")
text = text.replace("subtitle: Text('۱.۱.۱')", "subtitle: Text('۱.۱.۳')")
text = text.replace("subtitle: Text('۱.۱.۲')", "subtitle: Text('۱.۱.۳')")

path.write_text(text)
print("Patched lib/main.dart with runtime config handoff + duplicate-tag normalization")

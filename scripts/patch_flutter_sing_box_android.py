from pathlib import Path

roots = list(Path.home().glob('.pub-cache/hosted/*/flutter_sing_box-1.2.0'))
if not roots:
    raise SystemExit('flutter_sing_box 1.2.0 package not found in PUB_CACHE')
plugin = roots[0]

gradle = plugin / 'android/build.gradle.kts'
g = gradle.read_text()
g = g.replace('compileSdk = 37', 'compileSdk = 36')
gradle.write_text(g)

# Add a native MethodChannel handoff. Dart sends the final normalized JSON
# here; native Android writes it and updates native MMKV so the :remote VPN
# process always sees the exact runtime config.
plugin_kt = plugin / 'android/src/main/kotlin/com/clashsing/flutter_sing_box/FlutterSingBoxPlugin.kt'
p = plugin_kt.read_text()
if 'import com.tencent.mmkv.MMKV' not in p:
    p = p.replace(
        'import com.clashsing.flutter_sing_box.cs.SingBoxConnector\n',
        'import com.clashsing.flutter_sing_box.cs.SingBoxConnector\n'
        'import com.tencent.mmkv.MMKV\n'
        'import java.io.File\n',
        1,
    )

runtime_case = '''            "setRuntimeConfig" -> {
                try {
                    if (call.arguments !is Map<*, *>) {
                        result.error("INVALID_ARGUMENTS", "runtime config arguments missing", null)
                        return
                    }
                    val args = call.arguments as Map<*, *>
                    val content = args["content"] as String?
                    if (content.isNullOrBlank()) {
                        result.error("INVALID_CONFIG", "runtime config is empty", null)
                        return
                    }
                    val runtimeDir = File(PluginManager.appContext.filesDir, "cybermatrix_runtime")
                    runtimeDir.mkdirs()
                    val runtimeFile = File(runtimeDir, "using_config.json")
                    runtimeFile.writeText(content)
                    val profileKv = MMKV.mmkvWithID("cs_profile", MMKV.MULTI_PROCESS_MODE)
                    profileKv.encode("using_config", runtimeDir.absolutePath)
                    profileKv.sync()
                    result.success(runtimeFile.absolutePath)
                } catch (e: Exception) {
                    result.error("RUNTIME_CONFIG_ERROR", e.message, e)
                }
            }
'''
if '"setRuntimeConfig" -> {' not in p:
    marker = '            "startVpn" -> {\n'
    if marker not in p:
        raise SystemExit('startVpn case not found in FlutterSingBoxPlugin.kt')
    p = p.replace(marker, runtime_case + marker, 1)
plugin_kt.write_text(p)

# The upstream service used only using_config.json and rejected startup if the
# selected Profile object was unavailable. Prefer runtime config, then fall
# back to profile.path, and don't require profile metadata just to start VPN.
box = plugin / 'android/src/main/kotlin/io/nekohasekai/sfa/bg/BoxService.kt'
b = box.read_text()
old = '''            val configFile = ProfileManager.getUsingConfig()
            val profile = ProfileManager.getSelectedProfile()
            if (profile == null || !configFile.exists()) {
                stopAndAlert(Alert.EmptyConfiguration)
                return
            }
            val content = configFile.readText()
            if (content.isBlank()) {
                stopAndAlert(Alert.EmptyConfiguration)
                return
            }

            lastProfileName = profile.name
'''
new = '''            val usingConfigFile = ProfileManager.getUsingConfig()
            val profile = ProfileManager.getSelectedProfile()
            val profileConfigFile = profile?.typed?.path?.let { java.io.File(it) }
            val configFile = when {
                usingConfigFile.exists() && usingConfigFile.length() > 0L -> usingConfigFile
                profileConfigFile != null && profileConfigFile.exists() && profileConfigFile.length() > 0L -> profileConfigFile
                else -> null
            }
            if (configFile == null) {
                stopAndAlert(Alert.EmptyConfiguration, "CyberMatrix: runtime/profile config file not found")
                return
            }
            val content = configFile.readText()
            if (content.isBlank()) {
                stopAndAlert(Alert.EmptyConfiguration, "CyberMatrix: runtime config is blank: ${configFile.path}")
                return
            }

            lastProfileName = profile?.name ?: "CyberMatrix Tunnel"
'''
count = b.count(old)
if count == 0:
    raise SystemExit('BoxService config block not found')
b = b.replace(old, new)
box.write_text(b)
print(f'Patched {count} BoxService config blocks')

# Upstream sends service alerts only to Android logs. Mirror them into
# Flutter's log EventChannel so the app shows the actual startup error.
connector = plugin / 'android/src/main/kotlin/com/clashsing/flutter_sing_box/cs/SingBoxConnector.kt'
c = connector.read_text()
old_alert = '''        override fun onServiceAlert(type: Int, message: String?) {
            Log.e(TAG, "onServiceAlert: $type $message")
            proxyStatus = Status.Stopped
'''
new_alert = '''        override fun onServiceAlert(type: Int, message: String?) {
            Log.e(TAG, "onServiceAlert: $type $message")
            val alertText = "VPN_ALERT: ${message ?: "service alert type=$type"}"
            coroutineScope?.launch(Dispatchers.Main.immediate) {
                logSink?.success(Json.encodeToString(listOf(ClientLog(2, alertText))))
            }
            proxyStatus = Status.Stopped
'''
if old_alert not in c:
    raise SystemExit('onServiceAlert block not found')
c = c.replace(old_alert, new_alert, 1)
connector.write_text(c)

print('flutter_sing_box Android runtime patched successfully')

import 'package:flutter/material.dart';

void main() => runApp(const CyberMatrixApp());

class CyberMatrixApp extends StatelessWidget {
  const CyberMatrixApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CyberMatrix Tunnel',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF090D16),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C5CFF),
          brightness: Brightness.dark,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF121827),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: const AppShell(),
    );
  }
}

class ServerProfile {
  ServerProfile({
    required this.name,
    required this.protocol,
    required this.location,
    required this.ping,
  });

  final String name;
  final String protocol;
  final String location;
  final int ping;
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _page = 0;
  int _selected = 0;
  bool _connected = false;

  final List<ServerProfile> _servers = [
    ServerProfile(
      name: 'Germany 01',
      protocol: 'VLESS',
      location: 'Frankfurt',
      ping: 72,
    ),
    ServerProfile(
      name: 'Netherlands 01',
      protocol: 'VMess',
      location: 'Amsterdam',
      ping: 91,
    ),
    ServerProfile(
      name: 'Finland 01',
      protocol: 'Trojan',
      location: 'Helsinki',
      ping: 108,
    ),
  ];

  void _importConfig(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return;

    final lower = raw.toLowerCase();
    var protocol = 'Config';
    if (lower.startsWith('vless://')) protocol = 'VLESS';
    if (lower.startsWith('vmess://')) protocol = 'VMess';
    if (lower.startsWith('trojan://')) protocol = 'Trojan';
    if (lower.startsWith('ss://')) protocol = 'Shadowsocks';
    if (lower.startsWith('hysteria2://') || lower.startsWith('hy2://')) {
      protocol = 'Hysteria2';
    }

    var name = '$protocol ${_servers.length + 1}';
    final hash = raw.lastIndexOf('#');
    if (hash >= 0 && hash < raw.length - 1) {
      name = Uri.decodeComponent(raw.substring(hash + 1));
    }

    setState(() {
      _servers.add(
        ServerProfile(
          name: name,
          protocol: protocol,
          location: 'Imported',
          ping: 0,
        ),
      );
      _selected = _servers.length - 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomePage(
        connected: _connected,
        server: _servers[_selected],
        onToggle: () => setState(() => _connected = !_connected),
        onOpenServers: () => setState(() => _page = 1),
      ),
      ServersPage(
        servers: _servers,
        selected: _selected,
        onSelect: (index) => setState(() => _selected = index),
        onImport: _importConfig,
      ),
      ConfigPage(onImport: _importConfig),
      const SettingsPage(),
    ];

    return Scaffold(
      body: SafeArea(child: pages[_page]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _page,
        onDestinationSelected: (index) => setState(() => _page = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.shield_outlined),
            selectedIcon: Icon(Icons.shield),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.dns_outlined),
            selectedIcon: Icon(Icons.dns),
            label: 'Servers',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_link),
            label: 'Config',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.connected,
    required this.server,
    required this.onToggle,
    required this.onOpenServers,
  });

  final bool connected;
  final ServerProfile server;
  final VoidCallback onToggle;
  final VoidCallback onOpenServers;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Row(
          children: [
            Icon(Icons.bolt_rounded, size: 34),
            SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CyberMatrix',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                Text(
                  'T U N N E L',
                  style: TextStyle(fontSize: 10, color: Colors.white54),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 42),
        Center(
          child: GestureDetector(
            onTap: onToggle,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: connected
                      ? [scheme.primary, scheme.tertiary]
                      : [const Color(0xFF1A2234), const Color(0xFF0F1522)],
                ),
                border: Border.all(
                  color: connected ? scheme.primary : Colors.white12,
                  width: 2,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.power_settings_new_rounded, size: 58),
                  const SizedBox(height: 10),
                  Text(
                    connected ? 'CONNECTED' : 'CONNECT',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            connected ? 'Protected • prototype mode' : 'Tap to connect',
            style: TextStyle(
              color: connected ? scheme.primary : Colors.white54,
            ),
          ),
        ),
        const SizedBox(height: 34),
        Panel(
          child: ListTile(
            onTap: onOpenServers,
            leading: const Icon(Icons.public_rounded),
            title: Text(
              server.name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text('${server.location} • ${server.protocol}'),
            trailing: Text(server.ping == 0 ? '-- ms' : '${server.ping} ms'),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: MetricCard(
                icon: Icons.south_rounded,
                label: 'Download',
                value: connected ? '14.2 MB' : '0 B',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MetricCard(
                icon: Icons.north_rounded,
                label: 'Upload',
                value: connected ? '2.8 MB' : '0 B',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Panel(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'v0.1 UI prototype — VPNService and sing-box are the next milestone.',
              style: TextStyle(color: Colors.white60),
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
    required this.servers,
    required this.selected,
    required this.onSelect,
    required this.onImport,
  });

  final List<ServerProfile> servers;
  final int selected;
  final ValueChanged<int> onSelect;
  final ValueChanged<String> onImport;

  Future<void> _showImport(BuildContext context) async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add config'),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: 'vless://...  vmess://...  trojan://...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              onImport(controller.text);
              Navigator.pop(context);
            },
            child: const Text('Import'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Servers',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
              ),
            ),
            FilledButton.icon(
              onPressed: () => _showImport(context),
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        for (var i = 0; i < servers.length; i++) ...[
          Panel(
            child: ListTile(
              onTap: () => onSelect(i),
              leading: const Icon(Icons.dns_rounded),
              title: Text(
                servers[i].name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text('${servers[i].location} • ${servers[i].protocol}'),
              trailing: Icon(
                i == selected
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class ConfigPage extends StatefulWidget {
  const ConfigPage({super.key, required this.onImport});

  final ValueChanged<String> onImport;

  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Import Config',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'Paste VLESS, VMess, Trojan, Shadowsocks or Hysteria2 URI.',
          style: TextStyle(color: Colors.white54),
        ),
        const SizedBox(height: 22),
        TextField(
          controller: controller,
          minLines: 6,
          maxLines: 10,
          decoration: const InputDecoration(hintText: 'vless://...'),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: () {
            widget.onImport(controller.text);
            controller.clear();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Config imported locally')),
            );
          },
          icon: const Icon(Icons.download_rounded),
          label: const Text('Import config'),
        ),
      ],
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
        Text(
          'Settings',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        SizedBox(height: 20),
        Panel(
          child: Column(
            children: [
              ListTile(
                leading: Icon(Icons.route_outlined),
                title: Text('Routing'),
                subtitle: Text('Global • rule engine coming next'),
              ),
              Divider(height: 1),
              ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('CyberMatrix Tunnel'),
                subtitle: Text('Version 0.1.0'),
              ),
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
        color: const Color(0xFF111725),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: child,
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(height: 14),
            Text(label, style: const TextStyle(color: Colors.white54)),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

# CyberMatrix Tunnel

Flutter starter for an Android tunneling client inspired by V2Box-style UX.

## v0.1
- Home screen with connect/disconnect UI
- Server list and server selection
- Import placeholders for VLESS, VMess, Trojan, Shadowsocks and Hysteria2 URIs
- Dark CyberMatrix UI
- GitHub Actions workflow to build a release APK without Android Studio

> Important: v0.1 is a UI/prototype build. The connect button does not tunnel traffic yet. The next milestone is Android VPNService + sing-box integration.

## APK build
Every push to `main` triggers **Build Android APK** in GitHub Actions. When it finishes, download the `cybermatrix-tunnel-apk` artifact from the workflow run.

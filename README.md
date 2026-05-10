# Firewall Log Analyzer 🛡️

[![Flutter](https://flutter.dev/images/brand.svg)](https://flutter.dev) [![Dart](https://www.dartlang.org/web/icons/logo.svg)](https://dart.dev)

**Advanced mobile app for firewall log analysis, live threat monitoring, and server status dashboard. Supports Ubuntu logs, real-time packet capture, geo-IP threat mapping, and stateful automated mitigation.**

![App Icon](assets/icon/icon.png)

## ✨ Features

| Feature | Description |
|---------|-------------|
| **📊 Log Analysis** | Authoritative backend analysis for Ubuntu/Nginx/Apache logs with 0-100 severity scoring. |
| **🧠 Event Correlation** | Stateful detection of Kill-Chain progressions (Recon → Exploit) and Distributed Attacks. |
| **🛡️ Active Mitigation** | Automated IP blocking (iptables/netsh) based on reputation scores (0-200). |
| **📡 Live Monitoring** | Real-time packet capture, "Stop Connecting" controls, and system health snapshots. |
| **🚀 App Usage** | Monitor top processes by CPU and Memory usage directly from the dashboard. |
| **🔒 Restricted UI** | Premium forbidden page on public endpoints to hide backend internals from the web. |
| **🤖 Remote Control** | Telegram bot integration for alerts and remote `/stop <ip>` commands with PIN auth. |
| **📱 Premium UI/UX** | High-density, compact dashboard with glassmorphism and adaptive layouts for all devices. |
| **💾 Saved Activity** | Bookmark suspicious logs and track recent analysis history. |
| **🔄 Log Comparison** | Side-by-side aggregation and threat-level diffing between log files. |

## 🎨 Aesthetics & UX

Designed for professional security analysts, the application features:
- **High-Density Compact UI**: Optimized layout to see maximum data with minimum scrolling.
- **Modern Aesthetics**: Sleek glassmorphism, vibrant status indicators, and smooth micro-animations.
- **Adaptive Dashboards**: Responsive components that scale perfectly from mobile to desktop.
- **Dark Mode Mastery**: A premium dark-themed experience tailored for long monitoring sessions.

## 🚀 Quick Start (Flutter App)

1. **Install Flutter**: [flutter.dev](https://flutter.dev)
2. **Clone & Install**:
   ```bash
   git clone <repo>
   cd firewall_log_analyzer
   flutter pub get
   ```
3. **Run with Security Token**:
   ```bash
   # IMPORTANT: Token must match your backend APP_ACCESS_TOKEN
   flutter run --dart-define=APP_ACCESS_TOKEN=your_secret_token
   ```

**Latest Builds:** Pre-built APKs (v3.6.0+) are available in the `build/` directory.

## 🖥️ Server Backend Setup (Live Features)

The app connects to `packet_server.py` for live packet/log monitoring and stateful threat correlation.

### Requirements
```bash
python3 -m pip install -r requirements.txt  # scapy, websockets, psutil, firebase-admin, requests
```

### Run Server
```bash
# Set your secure token
export APP_ACCESS_TOKEN="your_secret_token"

# Full features on Linux (recommended)
sudo ./venv/bin/python3 packet_server.py --port 8765 --enable-logs

# Windows/MacOS basic mode (no root required)
python3 packet_server.py --port 8765 --no-packet-sniffing
```

**Key Features:**
- **Stateful Correlation**: Tracks attack stages over time via `EventCorrelationEngine`.
- **Reputation-based Blocking**: Auto-drops persistent attackers.
- **App Usage Monitoring**: Live `psutil` process monitoring for system overhead analysis.
- **Public Protection**: Public web access is blocked with a premium "Restricted Access" UI.
- **Telegram Admin**: Secure remote mitigation using the `/stop` command with PIN verification.
- **Firebase**: Push notifications for critical security events.
- **Service Monitoring**: Real-time status for Docker, Caddy, Cloudflare, and Tailscale.

**Connect from app:** Server Screen → Settings → Enter `ws://your-server:8765`

## 📊 Supported Log Formats

See [LOGS_QUICKSTART.md](LOGS_QUICKSTART.md) & [UBUNTU_LOGS.md](UBUNTU_LOGS.md) for:
- Ubuntu paths: `/var/log/kern.log`, `auth.log`, `syslog`
- Web server paths: Nginx access, Apache access
- Parser patterns in `lib/services/log_parser.dart`

## 📚 Documentation

Detailed information about the project can be found in:
- [PROJECT_DOCUMENTATION.md](PROJECT_DOCUMENTATION.md) - Comprehensive guide including Features, Ubuntu Logs, Implementation, and Roadmap.

## 🔨 Building & Signing

When building for production, you **must** provide the `APP_ACCESS_TOKEN` via `--dart-define`.

```bash
# Android (APK)
flutter build apk --release --dart-define=APP_ACCESS_TOKEN=Ab0526684921!

# Windows (EXE)
flutter build windows --dart-define=APP_ACCESS_TOKEN=Ab0526684921!

# iOS (macOS req'd)
flutter build ios --dart-define=APP_ACCESS_TOKEN=Ab0526684921!
```

**Signing:** Use `keystore/keystore.jks` for Android.

## 🤝 Contributing

1. Fork & PR
2. Follow Dart/Flutter style guide
3. Add tests (`test/widget_test.dart`)
4. Update documentation

## 📄 License

MIT License - see `LICENSE`.

---

**Engineered for Security. Powered by Flutter & Python.**

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
| **📡 Live Monitoring** | Real-time packet capture and system health snapshots via secure WebSockets. |
| **🤖 Remote Control** | Telegram bot integration for alerts and remote `/stop <ip>` commands with PIN auth. |
| **📱 Responsive UI** | Adaptive layout for phones, tablets, and foldables using `NavigationRail`. |
| **💾 Saved Activity** | Bookmark suspicious logs and track recent analysis history. |
| **🔄 Log Comparison** | Side-by-side aggregation and threat-level diffing between log files. |

## 🚀 Quick Start (Flutter App)

1. **Install Flutter**: [flutter.dev](https://flutter.dev)
2. **Clone & Install**:
   ```bash
   git clone <repo>
   cd firewall_log_analyzer
   flutter pub get
   ```
3. **Run**:
   ```bash
   flutter run
   ```

**Latest Builds:** Pre-built APKs (v3.5.0+) are available in the `build/` directory.

## 🖥️ Server Backend Setup (Live Features)

The app connects to `packet_server.py` for live packet/log monitoring and stateful threat correlation.

### Requirements
```bash
python3 -m pip install -r requirements.txt  # scapy, websockets, psutil, firebase-admin, requests
```

### Run Server
```bash
# Full features on Linux (recommended)
sudo ./venv/bin/python3 packet_server.py --port 8765 --enable-logs

# Windows/MacOS basic mode (no root required)
python3 packet_server.py --port 8765 --no-packet-sniffing
```

**Key Features:**
- **Stateful Correlation**: Tracks attack stages over time via `EventCorrelationEngine`.
- **Reputation-based Blocking**: Auto-drops persistent attackers.
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

- [project_overview.md](project_overview.md) - Full technical architecture
- [FEATURES_QUICKSTART.md](FEATURES_QUICKSTART.md) - User guide
- [IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md) - Implementation history
- [todo.md](todo.md) & [P1_TODO.md](P1_TODO.md) - Roadmap

## 🔨 Building & Signing

```bash
flutter build apk --release    # Android
flutter build ios              # iOS (macOS req'd)
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

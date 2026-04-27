import argparse
import asyncio
import collections
import contextlib
import hmac
import ipaddress
import json
import os
import platform
import re
import shutil
import socket
import sys
import time
import sqlite3
import threading
import queue
import subprocess
from datetime import datetime, timezone, timedelta
from http import HTTPStatus
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Set, Union
from urllib.parse import parse_qs, urlsplit


def exit_missing_dependency(module_name: str, error: ImportError) -> None:
    print(f"❌ Missing required Python package '{module_name}': {error}")
    print(f"Interpreter: {sys.executable}")
    print("Install dependencies with the same interpreter that will run packet_server.py.")

    repo_root = Path.cwd()
    linux_venv_python = repo_root / "venv" / "bin" / "python3"
    windows_venv_python = repo_root / "venv" / "Scripts" / "python.exe"

    if linux_venv_python.exists():
        print("Try one of these commands:")
        print(f"  {linux_venv_python} -m pip install -r requirements.txt")
        print(
            f"  sudo {linux_venv_python} packet_server.py --port 8765 --enable-logs"
        )
    elif windows_venv_python.exists():
        print("Try this command:")
        print(f"  {windows_venv_python} -m pip install -r requirements.txt")
    else:
        print("Try this command:")
        print(f"  {sys.executable} -m pip install -r requirements.txt")

    if platform.system() != "Windows":
        print("If you install a version spec directly, quote it, for example:")
        print("  python3 -m pip install 'websockets>=10.4'")
    raise SystemExit(1)


def format_timestamp_to_ist_ddmmyy(ts: str) -> str:
    if not ts:
        return ''
    try:
        dt = datetime.fromisoformat(ts.replace('Z', '+00:00'))
        ist = timezone(timedelta(hours=5, minutes=30))
        dt_ist = dt.astimezone(ist)
        return dt_ist.strftime('%d/%m/%y')
    except:
        return ts


try:
    import requests
except ImportError as error:
    exit_missing_dependency("requests", error)

# Firebase imports (optional)
try:
    import firebase_admin
    from firebase_admin import credentials, messaging
    FIREBASE_AVAILABLE = True
except ImportError:
    print("⚠️  firebase-admin not installed. Firebase notifications disabled.")
    FIREBASE_AVAILABLE = False
    firebase_admin = None
    credentials = None
    messaging = None

# Initialize Firebase (you'll need to place your service account key in the same directory)
if FIREBASE_AVAILABLE:
    try:
        cred = credentials.Certificate("firebase-service-account.json")
        firebase_admin.initialize_app(cred)
        print("✅ Firebase initialized successfully")
    except Exception as e:
        print(f"❌ Firebase initialization failed: {e}")
        print("Make sure firebase-service-account.json is in the current directory")
        FIREBASE_AVAILABLE = False
else:
    print("ℹ️  Running without Firebase notifications")

def load_env_file(path: Path = Path(".env")) -> None:
    """Load simple KEY=value pairs without requiring python-dotenv."""
    if not path.exists():
        return

    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as error:
        print(f"Warning: could not read {path}: {error}")
        return

    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue

        key, value = stripped.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value


load_env_file()

# 1. GeoIP Cache with Size Limit
geoip_cache = {}
MAX_GEOIP_CACHE_SIZE = 5000

def get_geoip(ip: str) -> dict:
    if ip in geoip_cache:
        return geoip_cache[ip]
    if not ip or ip.startswith("192.168.") or ip.startswith("10.") or ip.startswith("127.") or ip == "0.0.0.0":
        return {}
        
    # Simple LRU-ish eviction
    if len(geoip_cache) >= MAX_GEOIP_CACHE_SIZE:
        # Remove a random item or just clear (simple approach)
        try:
            it = iter(geoip_cache)
            for _ in range(100):
                next_key = next(it)
                del geoip_cache[next_key]
        except StopIteration:
            geoip_cache.clear()

    try:
        req = requests.get(f"http://ip-api.com/json/{ip}", timeout=2)
        if req.status_code == 200:
            data = req.json()
            if data and data.get("status") == "success":
                lat = data.get("lat")
                lon = data.get("lon")
                geo = {
                    "country": data.get("country"),
                    "city": data.get("city"),
                    "isp": data.get("isp"),
                    "lat": lat,
                    "lon": lon,
                    "latitude": lat,
                    "longitude": lon,
                }
                geoip_cache[ip] = geo
                geoip_cache[ip] = geo
                return geo
    except:
        pass
    geoip_cache[ip] = {}
    return {}

# 2. Active Mitigation
blocked_ips: Dict[str, float] = {}
REPUTATION_BLOCK_THRESHOLD = 150.0
REPUTATION_DECAY_RATE_PER_MINUTE = 5.0
MAX_REPUTATION_SCORE = 200.0
BLOCK_COOLDOWN_MINUTES = 60.0
ip_reputation: Dict[str, dict] = {}
TRUSTED_IPS = [
    "192.168.29.1",      # router
    "172.16.0.0/12",     # docker
]
REGISTERED_DEVICES_FILE = Path("registered_devices.json")
registered_devices: Dict[str, dict] = {}
FCM_TOKENS_FILE = Path("fcm_tokens.json")
THREAT_NOTIFICATION_COOLDOWN_SECONDS = float(
    os.getenv("THREAT_NOTIFICATION_COOLDOWN_SECONDS", "3600")
)
AUTO_BLOCK_THREATS = os.getenv("AUTO_BLOCK_THREATS", "false").strip().lower() in {
    "1",
    "true",
    "yes",
    "on",
}
DEFAULT_APP_ACCESS_TOKEN = os.getenv("PACKET_ANALYZER_TOKEN", "").strip()
MAX_HISTORY_LIMIT = 500
WS_RATE_LIMIT_WINDOW_SECONDS = 60
WS_RATE_LIMIT_MAX_HISTORY_REQUESTS = 15
TELEGRAM_BOT_TOKEN = (
    os.getenv("PACKET_ANALYZER_TELEGRAM_BOT_TOKEN")
    or os.getenv("TELEGRAM_BOT_TOKEN")
    or ""
).strip()
TELEGRAM_CHAT_ID = (
    os.getenv("PACKET_ANALYZER_TELEGRAM_CHAT_ID")
    or os.getenv("TELEGRAM_CHAT_ID")
    or ""
).strip()
TELEGRAM_ADMIN_PIN = os.getenv("PACKET_ANALYZER_TELEGRAM_PIN", "").strip()
telegram_command_rate_limits: Dict[str, float] = {}
TELEGRAM_ALERT_TIMEOUT_SECONDS = 2.0
PORT_SCAN_FAST_WINDOW_SECONDS = float(os.getenv("PORT_SCAN_FAST_WINDOW_SECONDS", "15"))
PORT_SCAN_FAST_MIN_UNIQUE_PORTS = int(os.getenv("PORT_SCAN_FAST_MIN_UNIQUE_PORTS", "20"))
PORT_SCAN_SLOW_WINDOW_SECONDS = float(os.getenv("PORT_SCAN_SLOW_WINDOW_SECONDS", "120"))
PORT_SCAN_SLOW_MIN_UNIQUE_PORTS = int(os.getenv("PORT_SCAN_SLOW_MIN_UNIQUE_PORTS", "25"))
MAX_PORT_SCAN_TRACKER_SIZE = 2000
port_scan_tracker: Dict[str, list[tuple[float, int]]] = {}
port_scan_active_sources: Set[str] = set()

# 3. Memory Monitoring Thresholds
SOFT_MEMORY_LIMIT_MB = 2048.0   # 2GB - Start aggressive cleanup
HARD_MEMORY_LIMIT_MB = 3072.0   # 3GB - Refuse expensive requests
CRITICAL_MEMORY_LIMIT_MB = 4096.0 # 4GB - Critical alert


def send_alert(msg: str) -> bool:
    """Send a Telegram alert if bot credentials are configured."""
    if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID:
        return False

    try:
        response = requests.post(
            f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage",
            data={
                "chat_id": TELEGRAM_CHAT_ID,
                "text": msg,
            },
            timeout=TELEGRAM_ALERT_TIMEOUT_SECONDS,
        )
        if response.status_code >= 400:
            print(f"Telegram alert failed: HTTP {response.status_code}")
            return False
        print("Telegram alert sent.")
        return True
    except Exception as error:
        print("Telegram alert failed:", error)
        return False


def queue_alert(msg: str) -> None:
    """Send Telegram alerts without blocking packet/log processing."""
    threading.Thread(target=send_alert, args=(msg,), daemon=True).start()


def telegram_command_worker(stop_event: threading.Event) -> None:
    """Poll Telegram for trusted chat commands such as /stop <ip>."""
    if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID:
        return

    offset: Optional[int] = None
    print(f"Telegram command listener enabled. Use /stop <ip> <pin> to block an IP.")
    if TELEGRAM_ADMIN_PIN == "0000":
        print("WARNING: Telegram Admin PIN is using default '0000'. Please set PACKET_ANALYZER_TELEGRAM_PIN.")
    while not stop_event.is_set():
        try:
            params: Dict[str, object] = {
                "timeout": 20,
                "allowed_updates": json.dumps(["message"]),
            }
            if offset is not None:
                params["offset"] = offset

            response = requests.get(
                f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/getUpdates",
                params=params,
                timeout=25,
            )
            if response.status_code >= 400:
                print(f"Telegram command polling failed: HTTP {response.status_code}")
                stop_event.wait(5)
                continue

            payload = response.json()
            for update in payload.get("result", []):
                update_id = update.get("update_id")
                if isinstance(update_id, int):
                    offset = update_id + 1

                message = update.get("message") or {}
                chat = message.get("chat") or {}
                if str(chat.get("id", "")) != TELEGRAM_CHAT_ID:
                    continue

                user_id = str(message.get("from", {}).get("id", "unknown"))
                now = time.time()
                
                # Rate limiting (5 seconds between commands)
                last_time = telegram_command_rate_limits.get(user_id, 0.0)
                if now - last_time < 5.0:
                    send_alert("⚠️ Rate limit exceeded. Please wait 5 seconds.")
                    continue
                telegram_command_rate_limits[user_id] = now

                parts = text.split()
                command = parts[0].split("@", 1)[0].lower()
                if command != "/stop":
                    continue

                if len(parts) < 3:
                    send_alert("Usage: /stop <ip> <pin>")
                    continue

                target_ip = parts[1].strip()
                supplied_pin = parts[2].strip()

                if supplied_pin != TELEGRAM_ADMIN_PIN:
                    print(f"SECURITY: Unauthorized /stop attempt for {target_ip} from Telegram ID {user_id}")
                    send_alert("❌ Invalid PIN. Command rejected.")
                    continue

                if block_ip(target_ip, force=True):
                    send_alert(f"✅ Blocked {target_ip} (Verified by PIN)")
                else:
                    send_alert(f"Could not block {target_ip}; check server logs.")
        except Exception as error:
            print("Telegram command polling failed:", error)
            stop_event.wait(5)


def normalize_fcm_token(raw_value: object) -> Optional[str]:
    if raw_value is None:
        return None
    token = str(raw_value).strip()
    return token or None


def load_registered_fcm_tokens() -> Set[str]:
    if not FCM_TOKENS_FILE.exists():
        return set()

    try:
        payload = json.loads(FCM_TOKENS_FILE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        print(f"Warning: could not read {FCM_TOKENS_FILE}: {error}")
        return set()

    if not isinstance(payload, list):
        return set()

    tokens = {token for item in payload if (token := normalize_fcm_token(item))}
    return tokens


def save_registered_fcm_tokens(tokens: Set[str]) -> None:
    try:
        FCM_TOKENS_FILE.write_text(
            json.dumps(sorted(tokens), indent=2),
            encoding="utf-8",
        )
    except OSError as error:
        print(f"Warning: could not save {FCM_TOKENS_FILE}: {error}")


def load_registered_devices() -> Dict[str, dict]:
    if not REGISTERED_DEVICES_FILE.exists():
        return {}

    try:
        payload = json.loads(REGISTERED_DEVICES_FILE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        print(f"Warning: could not read {REGISTERED_DEVICES_FILE}: {error}")
        return {}

    if not isinstance(payload, dict):
        return {}

    return payload


def save_registered_devices(devices: Dict[str, dict]) -> None:
    try:
        REGISTERED_DEVICES_FILE.write_text(
            json.dumps(devices, indent=2),
            encoding="utf-8",
        )
    except OSError as error:
        print(f"Warning: could not save {REGISTERED_DEVICES_FILE}: {error}")


def register_device(device_id: str, device_info: dict) -> None:
    """Register or update a device with detailed information."""
    registered_devices[device_id] = {
        **device_info,
        'registered_at': device_info.get('registered_at', iso_now()),
        'last_seen': iso_now(),
        'is_active': True,
    }
    save_registered_devices(registered_devices)


def update_device_activity(device_id: str, is_active: bool) -> None:
    """Update device activity status."""
    if device_id in registered_devices:
        registered_devices[device_id]['is_active'] = is_active
        registered_devices[device_id]['last_seen'] = iso_now()
        save_registered_devices(registered_devices)


def determine_threat_level(alerts: list[str]) -> str:
    joined = " ".join(alerts).upper()
    if any(
        phrase in joined
        for phrase in (
            "SQL INJECTION",
            "COMMAND INJECTION",
            "SENSITIVE FILE ACCESS",
        )
    ):
        return "critical"
    if any(
        phrase in joined
        for phrase in (
            "SCANNER",
            "CROSS-SITE SCRIPTING",
            "PATH TRAVERSAL",
        )
    ):
        return "high"
    return "medium"


def _compute_severity_score(alerts: list[str]) -> int:
    """Return a granular 0-100 severity score from a list of backend alert strings.

    Each alert type adds a weighted score; multiple alerts stack up to 100.
    This lets Flutter display a numeric value rather than just a band label,
    preserving room for future finer-grained scoring without app changes.
    """
    if not alerts:
        return 0

    _WEIGHTS: Dict[str, int] = {
        "SQL INJECTION":        40,
        "COMMAND INJECTION":    40,
        "SENSITIVE FILE ACCESS": 32,
        "CROSS-SITE SCRIPTING": 28,
        "PATH TRAVERSAL":       26,
        "SCANNER AGENT":        22,
        "PORT SCAN":            18,
    }

    score = 0
    for alert in alerts:
        upper = alert.upper()
        matched = False
        for keyword, weight in _WEIGHTS.items():
            if keyword in upper:
                score += weight
                matched = True
                break
        if not matched:
            score += 10  # generic alert

    return min(score, 100)


def build_threat_notification(
    payload: Dict[str, object],
    alerts: list[str],
    source_type: str,
) -> tuple[str, str, Dict[str, str]]:
    level = determine_threat_level(alerts)
    source_ip = str(
        payload.get("sourceIp")
        or payload.get("srcIp")
        or payload.get("ipAddress")
        or "unknown"
    )
    destination = str(payload.get("dstIp") or payload.get("url") or "unknown")
    protocol = str(payload.get("protocol") or payload.get("method") or "unknown")
    primary_alert = alerts[0]
    title = f"{level.title()} threat detected"
    body = f"{primary_alert} from {source_ip} via {protocol}"

    if destination and destination != "unknown":
        body = f"{body} to {destination}"
    if len(body) > 180:
        body = body[:177] + "..."

    data = {
        "type": "security_alert",
        "level": level,
        "title": title,
        "body": body,
        "source_type": source_type,
        "source_ip": source_ip,
        "destination": destination,
        "protocol": protocol,
        "alert_count": str(len(alerts)),
        "alerts": " | ".join(alerts)[:300],
        "timestamp": str(payload.get("timestamp") or iso_now()),
    }
    return title, body, data


def build_telegram_alert_message(
    payload: Dict[str, object],
    alerts: list[str],
    source_type: str,
) -> str:
    source_ip = str(
        payload.get("sourceIp")
        or payload.get("srcIp")
        or payload.get("ipAddress")
        or "unknown"
    )
    destination = str(payload.get("dstIp") or payload.get("url") or "unknown")
    protocol = str(payload.get("protocol") or payload.get("method") or "unknown")
    timestamp = str(payload.get("timestamp") or iso_now())
    level = determine_threat_level(alerts).upper()
    alert_text = "\n".join(f"- {alert}" for alert in alerts)
    stop_command = f"/stop {source_ip}" if source_ip != "unknown" else "/stop <ip>"

    return (
        "ATTACK DETECTED\n\n"
        f"Level: {level}\n"
        f"Source: {source_ip}\n"
        f"Destination: {destination}\n"
        f"Protocol: {protocol}\n"
        f"Source Type: {source_type}\n"
        f"Time: {timestamp}\n\n"
        f"Alerts:\n{alert_text}\n\n"
        f"Block command: {stop_command}\n"
        "Action required: review traffic and block the source if needed."
    )


def is_trusted_ip(ip: str) -> bool:
    """Check if an IP address is in the trusted list."""
    import ipaddress
    try:
        ip_obj = ipaddress.ip_address(ip)
        for trusted in TRUSTED_IPS:
            if "/" in trusted:
                # CIDR notation
                network = ipaddress.ip_network(trusted, strict=False)
                if ip_obj in network:
                    return True
            else:
                # Exact match
                if ip == trusted:
                    return True
        return False
    except ValueError:
        return False


def detect_port_scan(payload: dict) -> Optional[str]:
    protocol = str(payload.get("protocol") or "").upper()
    if protocol not in {"TCP", "UDP"}:
        return None

    source_ip = str(
        payload.get("sourceIp")
        or payload.get("srcIp")
        or payload.get("ipAddress")
        or ""
    ).strip()
    if (
        not source_ip
        or source_ip == "0.0.0.0"
        or source_ip.startswith("127.")
        or is_trusted_ip(source_ip)
    ):
        return None

    try:
        destination_port = int(payload.get("dstPort") or payload.get("port") or 0)
    except (TypeError, ValueError):
        return None

    if destination_port <= 0:
        return None

    now = time.time()
    cutoff = now - PORT_SCAN_SLOW_WINDOW_SECONDS
    samples = [
        (seen_at, port)
        for seen_at, port in port_scan_tracker.get(source_ip, [])
        if seen_at >= cutoff
    ]
    samples.append((now, destination_port))
    
    # Manage tracker size
    if len(port_scan_tracker) >= MAX_PORT_SCAN_TRACKER_SIZE and source_ip not in port_scan_tracker:
        # Evict oldest 100 IPs
        try:
            oldest_ips = sorted(port_scan_tracker.keys(), key=lambda k: port_scan_tracker[k][0][0] if port_scan_tracker[k] else 0)[:100]
            for old_ip in oldest_ips:
                del port_scan_tracker[old_ip]
        except:
            pass

    port_scan_tracker[source_ip] = samples

    fast_cutoff = now - PORT_SCAN_FAST_WINDOW_SECONDS
    fast_unique_ports = {
        port for seen_at, port in samples if seen_at >= fast_cutoff
    }
    slow_unique_ports = {port for _, port in samples}

    alert_window = None
    unique_port_count = 0
    if len(fast_unique_ports) >= PORT_SCAN_FAST_MIN_UNIQUE_PORTS:
        alert_window = PORT_SCAN_FAST_WINDOW_SECONDS
        unique_port_count = len(fast_unique_ports)
    elif len(slow_unique_ports) >= PORT_SCAN_SLOW_MIN_UNIQUE_PORTS:
        alert_window = PORT_SCAN_SLOW_WINDOW_SECONDS
        unique_port_count = len(slow_unique_ports)

    if alert_window is None:
        port_scan_active_sources.discard(source_ip)
        return None

    if source_ip in port_scan_active_sources:
        return None

    port_scan_active_sources.add(source_ip)
    print(
        "Port scan detector triggered: "
        f"{source_ip} hit {unique_port_count} ports in "
        f"{int(alert_window)}s"
    )
    payload["portScanUniquePorts"] = unique_port_count
    payload["portScanWindowSeconds"] = int(alert_window)
    return "Port Scan Detected"


def block_ip(ip: str, *, force: bool = False) -> bool:
    raw_ip = str(ip or "").strip()
    now = time.time()
    if not raw_ip:
        return False
    if raw_ip in blocked_ips and (now - blocked_ips[raw_ip]) < (BLOCK_COOLDOWN_MINUTES * 60):
        return False

    try:
        parsed_ip = ipaddress.ip_address(raw_ip)
    except ValueError:
        print(f"Invalid IP for blocking: {raw_ip}")
        return False

    if not force and (parsed_ip.is_private or parsed_ip.is_loopback):
        return False

    print(f"!!! ACTIVE MITIGATION !!! Blocking IP {raw_ip}")
    success = False
    if platform.system() == "Windows":
        try:
            result = subprocess.run(
                [
                    "netsh",
                    "advfirewall",
                    "firewall",
                    "add",
                    "rule",
                    f"name=Block_{raw_ip}",
                    "dir=in",
                    "action=block",
                    f"remoteip={raw_ip}",
                ],
                check=False,
            )
            success = result.returncode == 0
        except Exception as error:
            print("Failed to block on Windows:", error)
    elif platform.system() == "Linux":
        command = "ip6tables" if parsed_ip.version == 6 else "iptables"
        try:
            inbound = subprocess.run(
                [command, "-A", "INPUT", "-s", raw_ip, "-j", "DROP"],
                check=False,
            )
            outbound = subprocess.run(
                [command, "-A", "OUTPUT", "-d", raw_ip, "-j", "DROP"],
                check=False,
            )
            success = inbound.returncode == 0 and outbound.returncode == 0
        except Exception as error:
            print(f"Failed to block on Linux with {command}:", error)

    if success:
        blocked_ips[raw_ip] = now
    else:
        print(f"Failed to block IP {raw_ip}")
    return success

def extract_real_ip(payload: dict, default_ip: str) -> str:
    text_to_scan = " ".join(
        str(payload.get(field, ""))
        for field in ("data", "message", "request", "raw", "userAgent")
    )
    cf_match = re.search(r'CF-Connecting-IP[=:]\s*([0-9a-fA-F:.]+)', text_to_scan, re.IGNORECASE)
    if cf_match:
        return cf_match.group(1).strip()
    xf_match = re.search(r'X-Forwarded-For[=:]\s*([0-9a-fA-F:.]+)', text_to_scan, re.IGNORECASE)
    if xf_match:
        return xf_match.group(1).split(',')[0].strip()
    return default_ip

class EventCorrelationEngine:
    """Stateful engine to correlate security events over time."""
    def __init__(self, window_seconds: int = 900):
        self.window_seconds = window_seconds
        self.ip_signals: Dict[str, collections.deque] = {}
        self.global_signals: collections.deque = collections.deque()
        self.lock = threading.Lock()
        self.MAX_GLOBAL_SIGNALS = 5000
        self.MAX_TRACKED_IPS = 1000

    def add_signal(self, ip: str, alerts: list, payload: dict) -> list[str]:
        if not alerts or is_trusted_ip(ip):
            return []
            
        now = time.time()
        signal = {
            "timestamp": now,
            "ip": ip,
            "alerts": alerts,
            "type": payload.get("type", "unknown")
        }
        
        correlated = []
        with self.lock:
            # Update IP-specific history
            if ip not in self.ip_signals:
                # Prevent infinite IP tracking
                if len(self.ip_signals) >= self.MAX_TRACKED_IPS:
                    # Remove the IP with the oldest signal
                    try:
                        oldest_ip = min(self.ip_signals.keys(), 
                                      key=lambda k: self.ip_signals[k][0]["timestamp"] if self.ip_signals[k] else 0)
                        del self.ip_signals[oldest_ip]
                    except:
                        pass
                self.ip_signals[ip] = collections.deque()
            
            ip_queue = self.ip_signals[ip]
            ip_queue.append(signal)
            while ip_queue and now - ip_queue[0]["timestamp"] > self.window_seconds:
                ip_queue.popleft()
            
            # Update global signal pool (smaller window)
            self.global_signals.append(signal)
            while self.global_signals and (now - self.global_signals[0]["timestamp"] > 300 or len(self.global_signals) > self.MAX_GLOBAL_SIGNALS):
                self.global_signals.popleft()
            
            # Run Correlation Rules
            correlated.extend(self._check_kill_chain(ip, ip_queue))
            correlated.extend(self._check_distributed_attack(signal))
            
        return correlated

    def _check_kill_chain(self, ip: str, signals: collections.deque) -> list[str]:
        """Detect progression from reconnaissance to exploitation."""
        has_recon = False
        recon_types = {"Scanner Agent Detected", "Port Scan Detected", "Anomalous Traffic Burst"}
        exploit_types = {
            "SQL Injection Attempt", 
            "Cross-Site Scripting Attempt", 
            "Path Traversal Attempt", 
            "Sensitive File Access Attempt",
            "Command Injection Attempt",
            "SSH Brute Force Attempt"
        }
        
        for s in signals:
            s_alerts = set(s["alerts"])
            if s_alerts.intersection(recon_types):
                has_recon = True
            elif has_recon and s_alerts.intersection(exploit_types):
                trigger = list(s_alerts.intersection(exploit_types))[0]
                return [f"Kill-Chain Progression: Recon -> {trigger}"]
        return []

    def _check_distributed_attack(self, current_signal: dict) -> list[str]:
        """Detect the same attack signature across multiple IPs."""
        distinct_ips = set()
        alert_to_check = None
        
        # We only care about exploitation attempts for distributed detection
        exploit_types = {
            "SQL Injection Attempt", 
            "Cross-Site Scripting Attempt", 
            "Command Injection Attempt"
        }
        
        current_alerts = [a for a in current_signal["alerts"] if a in exploit_types]
        if not current_alerts:
            return []
            
        alert_to_check = current_alerts[0]
        
        for s in self.global_signals:
            if alert_to_check in s["alerts"]:
                distinct_ips.add(s["ip"])
        
        if len(distinct_ips) >= 5:
            return [f"Distributed Attack: '{alert_to_check}' from {len(distinct_ips)} distinct IPs"]
        return []

correlation_engine = EventCorrelationEngine()

def update_and_check_reputation(ip: str, alerts: list[str]) -> bool:
    if not alerts or is_trusted_ip(ip):
        return False
        
    now = time.time()
    if ip in blocked_ips and (now - blocked_ips[ip]) < (BLOCK_COOLDOWN_MINUTES * 60):
        return False
        
    rep = ip_reputation.get(ip, {"score": 0.0, "last_updated": now})
    
    minutes_elapsed = (now - rep["last_updated"]) / 60.0
    decay = minutes_elapsed * REPUTATION_DECAY_RATE_PER_MINUTE
    decayed_score = max(0.0, rep["score"] - decay)
    
    event_score = float(_compute_severity_score(alerts))
    new_score = min(decayed_score + event_score, MAX_REPUTATION_SCORE)
    
    # Manage reputation dict size (keep top 5000)
    if len(ip_reputation) >= 5000 and ip not in ip_reputation:
        try:
            # Remove 500 lowest-reputation/oldest records
            to_remove = sorted(ip_reputation.keys(), key=lambda k: ip_reputation[k]["last_updated"])[:500]
            for old_ip in to_remove:
                del ip_reputation[old_ip]
        except:
            pass

    ip_reputation[ip] = {"score": new_score, "last_updated": now}
    
    # Persistent Sync
    try:
        db_queue.put_nowait(("REP_UPDATE", ip, new_score, now))
    except queue.Full:
        pass
    
    return new_score >= REPUTATION_BLOCK_THRESHOLD

def analyze_for_threats(payload: dict) -> list:
    alerts = []
    text_to_scan = " ".join(
        str(payload.get(field, ""))
        for field in ("data", "message", "request", "raw", "url", "userAgent")
    ).upper()
    port_scan_alert = detect_port_scan(payload)
    if port_scan_alert:
        alerts.append(port_scan_alert)
    if "UNION" in text_to_scan and "SELECT" in text_to_scan:
        alerts.append("SQL Injection Attempt")
    if "AUTHENTICATION FAILURE" in text_to_scan or "FAILED PASSWORD" in text_to_scan or "INVALID USER" in text_to_scan:
        alerts.append("SSH Brute Force Attempt")
    if "NMAP" in text_to_scan or "NIKTO" in text_to_scan or "SQLMAP" in text_to_scan:
        alerts.append("Scanner Agent Detected")
    if "<SCRIPT" in text_to_scan or "ONERROR=" in text_to_scan or "ONLOAD=" in text_to_scan:
        alerts.append("Cross-Site Scripting Attempt")
    if "../" in text_to_scan or "..\\" in text_to_scan or "%2E%2E%2F" in text_to_scan:
        alerts.append("Path Traversal Attempt")
    if (
        "/ETC/PASSWD" in text_to_scan
        or "WIN.INI" in text_to_scan
        or ".HTACCESS" in text_to_scan
    ):
        alerts.append("Sensitive File Access Attempt")
    if " POWERSHELL " in f" {text_to_scan} " or " CMD.EXE " in f" {text_to_scan} " or " /BIN/BASH " in f" {text_to_scan} ":
        alerts.append("Command Injection Attempt")
    if "VIEW-CONFIG" in text_to_scan and "PASSWD" in text_to_scan:
        alerts.append("Sensitive File Access Attempt")
    if "FILE=" in text_to_scan and ("../" in text_to_scan or "..\\" in text_to_scan):
        alerts.append("Path Traversal Attempt")
    
    alerts = list(dict.fromkeys(alerts))
    
    # Run Correlation Engine
    raw_ip = str(payload.get("sourceIp") or payload.get("srcIp") or payload.get("ipAddress") or "")
    real_ip = extract_real_ip(payload, raw_ip)
    
    correlated_alerts = correlation_engine.add_signal(real_ip, alerts, payload)
    if correlated_alerts:
        alerts.extend(correlated_alerts)
        alerts = list(dict.fromkeys(alerts))

    if AUTO_BLOCK_THREATS and alerts:
        if real_ip and real_ip != "0.0.0.0" and not real_ip.startswith("127."):
            if update_and_check_reputation(real_ip, alerts):
                block_ip(real_ip)
    return alerts

def load_reputation_from_db():
    """Load IP reputation data from SQLite at startup."""
    try:
        conn = sqlite3.connect("firewall_insane.db")
        cursor = conn.cursor()
        cursor.execute("SELECT ip, score, last_updated FROM reputation")
        rows = cursor.fetchall()
        for ip, score, last_updated in rows:
            ip_reputation[ip] = {"score": score, "last_updated": last_updated}
        conn.close()
        if rows:
            print(f"Loaded {len(rows)} IP reputation records from database.")
    except Exception as e:
        print(f"Note: Could not load existing reputation: {e}")

# 3. SQLite Database Background Writer 
db_queue = queue.Queue(maxsize=10000)

def db_writer_thread():
    conn = sqlite3.connect("firewall_insane.db", check_same_thread=False)
    conn.execute("PRAGMA journal_mode=WAL;")
    conn.execute("PRAGMA synchronous=NORMAL;")
    cursor = conn.cursor()
    cursor.execute('''CREATE TABLE IF NOT EXISTS events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT,
        type TEXT,
        ip TEXT,
        payload TEXT
    )''')
    cursor.execute('''CREATE TABLE IF NOT EXISTS reputation (
        ip TEXT PRIMARY KEY,
        score REAL,
        last_updated REAL
    )''')
    conn.commit()
    
    batch = []
    while True:
        try:
            item = db_queue.get(timeout=1.0)
            if item is None:
                break
            
            if isinstance(item, tuple) and item[0] == "REP_UPDATE":
                _, ip, score, last_updated = item
                cursor.execute(
                    "INSERT OR REPLACE INTO reputation (ip, score, last_updated) VALUES (?, ?, ?)",
                    (ip, score, last_updated)
                )
                conn.commit()
                continue

            batch.append(item)
            if len(batch) >= 500 or db_queue.empty():
                cursor.executemany(
                    "INSERT INTO events (timestamp, type, ip, payload) VALUES (?, ?, ?, ?)",
                    batch
                )
                conn.commit()
                batch.clear()
        except queue.Empty:
            if batch:
                cursor.executemany(
                    "INSERT INTO events (timestamp, type, ip, payload) VALUES (?, ?, ?, ?)",
                    batch
                )
                conn.commit()
                batch.clear()

threading.Thread(target=db_writer_thread, daemon=True).start()

SERVER_LOG_SOURCE_PATHS: Dict[str, str] = {
    "auth":      "/var/log/auth.log",
    "syslog":    "/var/log/syslog",
    "ufw":       "/var/log/ufw.log",
    "tailscale": "/var/log/tailscale/tailscaled.log",
}


def tail_file_lines(path: str, limit: int) -> list[str]:
    try:
        result = subprocess.run(
            ["tail", "-n", str(limit), path],
            capture_output=True,
            text=True,
            timeout=3,
        )
        if result.returncode == 0:
            return result.stdout.splitlines()
    except Exception as e:
        print(f"DEBUG: tail subprocess failed for {path}: {e}")

    try:
        file_path = Path(path)
        with file_path.open("r", encoding="utf-8", errors="ignore") as handle:
            lines = handle.readlines()
        return [line.rstrip("\n") for line in lines[-limit:]]
    except Exception as e:
        print(f"DEBUG: direct file read failed for {path}: {e}")
        return []


def get_log_history(source: str, limit: int = 100, offset: int = 0, on_log_parsed: Optional[Callable] = None) -> Optional[list]:
    if limit <= 0:
        return []

    log_path = SERVER_LOG_SOURCE_PATHS.get(source)
    if log_path is None and source.startswith("/"):
        log_path = source

    if not log_path:
        return None

    path_obj = Path(log_path)
    if not path_obj.exists():
        return []

    # Strictly limit lines to prevent memory overflow on large log files
    safe_limit = min(limit + max(offset, 0), 2000) 
    lines = tail_file_lines(log_path, safe_limit)
    if not lines:
        return []

    parsed_logs = []
    source_name = source if SERVER_LOG_SOURCE_PATHS.get(source) else path_obj.stem
    for line in lines:
        if not line.strip():
            continue
        parsed = parse_ubuntu_log_line(line, source_name)
        if parsed:
            src = parsed.get("sourceIp") or parsed.get("ipAddress")
            if isinstance(src, str):
                geo_info = get_geoip(src)
                if geo_info:
                    parsed.update(geo_info)

            # ── Backend-authority threat enrichment ──────────────────────────
            # This mirrors log_callback() so the history path is consistent
            # with live-tailing: Flutter always gets alerts/threatLevel/
            # severityScore in the payload and never needs to re-analyze.
            alerts = analyze_for_threats(parsed)
            if alerts:
                parsed["alerts"]        = alerts
                parsed["threatLevel"]   = determine_threat_level(alerts)
                parsed["severityScore"] = _compute_severity_score(alerts)
            # -----------------------------------------------------------------
            parsed_logs.append(parsed)
            if on_log_parsed:
                on_log_parsed(parsed, len(parsed_logs), len(lines))

    return parsed_logs[offset : offset + limit]


def get_history(
    event_type: str,
    limit: int = 100,
    source: Optional[str] = None,
    offset: int = 0,
    on_log_parsed: Optional[Callable] = None,
):
    if event_type == "log" and source:
        log_history = get_log_history(source, limit, offset, on_log_parsed)
        if log_history is not None:
            return log_history

    try:
        conn = sqlite3.connect("firewall_insane.db")
        cursor = conn.cursor()
        # Optimization: Don't fetch everything at once.
        # We use a safety multiplier (x5) to allow for source filtering while still limiting memory.
        safe_db_limit = limit * 5
        cursor.execute(
            "SELECT payload FROM events WHERE type = ? ORDER BY id DESC LIMIT ?",
            (event_type, safe_db_limit),
        )
        rows = cursor.fetchall()
        conn.close()
        normalized_source = (source or "").strip().lower()
        history = []
        skipped = 0
        for row in rows:
            payload = json.loads(row[0])
            if normalized_source:
                payload_source = str(payload.get("source", "")).strip().lower()
                payload_parameters = str(payload.get("parameters", "")).strip().lower()
                if payload_source != normalized_source and payload_parameters != normalized_source:
                    continue
            if skipped < max(offset, 0):
                skipped += 1
                continue
            history.append(payload)
            if len(history) >= limit:
                break
        return list(reversed(history))
    except sqlite3.OperationalError:
        return []

# 4. Cloud Status Monitoring Functions

def get_cloud_status() -> Dict[str, Any]:
    """Get cloud infrastructure status."""
    status = {
        "docker": "DOWN",
        "caddy": "DOWN",
        "cloudflare_tunnel": "DOWN",
        "landing_page": "DOWN",
        "portainer": "DOWN",
        "tailscale": "DOWN",
        "public_domain": "DOWN",
    }
    
    try:
        # Check Docker
        result = subprocess.run(["systemctl", "is-active", "docker"], capture_output=True, timeout=2)
        if result.returncode == 0:
            status["docker"] = "active"
    except Exception:
        pass
    
    try:
        # Check Docker containers
        result = subprocess.run(
            ["docker", "ps", "--format", "{{.Names}}"],
            capture_output=True,
            timeout=2,
            text=True
        )
        if result.returncode == 0:
            containers = result.stdout.strip().split("\n")
            if "caddy" in containers:
                status["caddy"] = "OK"
            if "cloudflared" in containers:
                status["cloudflare_tunnel"] = "OK"
            if "landing" in containers:
                status["landing_page"] = "OK"
            if "portainer" in containers:
                status["portainer"] = "OK"
    except Exception:
        pass
    
    try:
        # Check Tailscale
        result = subprocess.run(["tailscale", "status"], capture_output=True, timeout=2, text=True)
        if result.returncode == 0 and "noodleos" in result.stdout:
            status["tailscale"] = "OK"
    except Exception:
        pass
    
    try:
        # Check public domain
        result = requests.get("https://plexaur.com", timeout=2)
        if result.status_code == 200:
            status["public_domain"] = "LIVE"
    except Exception:
        pass
    
    return status

def get_docker_containers() -> list[dict[str, str]]:
    """Get Docker container details as structured status records."""
    containers = []
    try:
        result = subprocess.run(
            ["docker", "ps", "-a", "--format", "{{json .}}"],
            capture_output=True,
            timeout=5,
            text=True
        )
        if result.returncode == 0:
            for line in result.stdout.splitlines():
                line = line.strip()
                if not line:
                    continue
                try:
                    record = json.loads(line)
                except json.JSONDecodeError:
                    continue

                containers.append({
                    "id": str(record.get("ID", "")),
                    "image": str(record.get("Image", "")),
                    "name": str(record.get("Names", "")),
                    "state": str(record.get("State", "")),
                    "status": str(record.get("Status", "")),
                })
    except Exception:
        pass
    
    return containers

cached_active_ssh_sessions = []

def update_ssh_sessions_thread():
    global cached_active_ssh_sessions
    while True:
        try:
            result = subprocess.run(["who"], capture_output=True, text=True, timeout=5)
            if result.returncode == 0:
                sessions = []
                for line in result.stdout.strip().split("\n"):
                    if not line:
                        continue
                    parts = line.split()
                    if len(parts) >= 5:
                        user = parts[0]
                        tty = parts[1]
                        login_time = f"{parts[2]} {parts[3]}"
                        ip = parts[-1].strip("()") if "(" in parts[-1] else "unknown"
                        if ip == "unknown" and len(parts) >= 6:
                            ip = parts[5].strip("()")
                        sessions.append({
                            "user": user,
                            "tty": tty,
                            "ip": ip,
                            "connectedAt": login_time,
                        })
                cached_active_ssh_sessions = sessions
        except Exception:
            pass
        time.sleep(5)

# Start the thread immediately
threading.Thread(target=update_ssh_sessions_thread, daemon=True).start()

def get_active_ssh_sessions() -> list[dict]:
    return list(cached_active_ssh_sessions)

try:
    import websockets
    try:
        from websockets.http11 import Response as WSResponse
        from websockets.datastructures import Headers as WSHeaders
    except ImportError:
        WSResponse = None
        WSHeaders = None
except ImportError as error:
    exit_missing_dependency("websockets", error)

try:
    from scapy.all import AsyncSniffer, IP, IPv6, TCP, UDP
except ImportError as error:
    exit_missing_dependency("scapy", error)

try:
    import psutil
except ImportError:  # pragma: no cover
    psutil = None


def iso_now() -> str:
    return datetime.now(timezone.utc).isoformat()

def sanitize_log_field(value: object) -> object:
    if isinstance(value, str):
        val = value.replace("<", "&lt;").replace(">", "&gt;")
        val = re.sub(r'\x1B\[[0-?]*[ -/]*[@-~]', '', val)
        return val
    elif isinstance(value, dict):
        return {k: sanitize_log_field(v) for k, v in value.items()}
    elif isinstance(value, list):
        return [sanitize_log_field(v) for v in value]
    return value


def format_uptime(total_seconds: int) -> str:
    days, remainder = divmod(max(total_seconds, 0), 86400)
    hours, remainder = divmod(remainder, 3600)
    minutes, seconds = divmod(remainder, 60)
    parts = []
    if days:
        parts.append(f"{days}d")
    if hours or parts:
        parts.append(f"{hours}h")
    if minutes or parts:
        parts.append(f"{minutes}m")
    parts.append(f"{seconds}s")
    return " ".join(parts)


def read_text(path: Path) -> Optional[str]:
    try:
        return path.read_text(encoding="utf-8").strip()
    except OSError:
        return None


def get_local_ip() -> str:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect(("8.8.8.8", 80))
        return sock.getsockname()[0]
    except OSError:
        return socket.gethostbyname(socket.gethostname())
    finally:
        sock.close()


def is_address_in_use_error(error: OSError) -> bool:
    if error.errno in {48, 98, 10048}:
        return True
    return "address already in use" in str(error).lower()


def get_uptime_seconds() -> int:
    if psutil is not None:
        return int(time.time() - psutil.boot_time())

    uptime_value = read_text(Path("/proc/uptime"))
    if uptime_value:
        return int(float(uptime_value.split()[0]))
    return 0


def get_memory_info() -> Dict[str, Optional[Union[int, float]]]:
    if psutil is not None:
        memory = psutil.virtual_memory()
        return {
            "memoryTotalMb": round(memory.total / (1024 * 1024)),
            "memoryUsedMb": round(memory.used / (1024 * 1024)),
            "memoryUsagePercent": round(memory.percent, 1),
        }

    meminfo_path = Path("/proc/meminfo")
    if not meminfo_path.exists():
        return {
            "memoryTotalMb": None,
            "memoryUsedMb": None,
            "memoryUsagePercent": None,
        }

    meminfo = {}
    for line in meminfo_path.read_text(encoding="utf-8").splitlines():
        key, _, value = line.partition(":")
        meminfo[key] = value.strip()

    total_kb = int(meminfo.get("MemTotal", "0 kB").split()[0])
    available_kb = int(meminfo.get("MemAvailable", "0 kB").split()[0])
    used_kb = max(total_kb - available_kb, 0)
    usage_percent = round((used_kb / total_kb) * 100, 1) if total_kb else 0.0
    return {
        "memoryTotalMb": round(total_kb / 1024),
        "memoryUsedMb": round(used_kb / 1024),
        "memoryUsagePercent": usage_percent,
    }


def get_cpu_usage_percent() -> Optional[float]:
    if psutil is None:
        return None
    return round(psutil.cpu_percent(interval=None), 1)


def get_battery_info() -> Dict[str, Optional[Union[bool, int, str]]]:
    print(f"🔋 Checking battery on {platform.system()}...")
    
    if psutil is not None:
        try:
            battery = psutil.sensors_battery()
            if battery is not None:
                percent = round(battery.percent)
                print(f"🔋 psutil detected battery: {percent}% ({'Charging' if battery.power_plugged else 'Discharging'})")
                return {
                    "batteryPresent": True,
                    "batteryPercent": percent,
                    "isCharging": battery.power_plugged,
                    "batteryStatus": "Charging" if battery.power_plugged else "Not charging",
                    "batterySecsLeft": battery.secsleft,
                }
            else:
                print("🔋 psutil: No battery detected")
        except Exception as e:
            print(f"🔋 psutil error: {e}")
    else:
        print("🔋 psutil not available")

    power_root = Path("/sys/class/power_supply")
    if power_root.exists():
        print("🔋 Checking Linux battery...")
        for entry in power_root.iterdir():
            if read_text(entry / "type") != "Battery":
                continue
            percent = read_text(entry / "capacity")
            status = read_text(entry / "status") or "Unknown"
            if percent and percent.isdigit():
                percent_int = int(percent)
                print(f"🔋 Linux battery: {percent_int}% ({status})")
                return {
                    "batteryPresent": True,
                    "batteryPercent": percent_int,
                    "isCharging": status.lower() == "charging",
                    "batteryStatus": status,
                    "batterySecsLeft": None,
                }
    
    print("🔋 No battery detected")
    return {
        "batteryPresent": False,
        "batteryPercent": None,
        "isCharging": None,
        "batteryStatus": "Unavailable",
        "batterySecsLeft": None,
    }


def default_battery_info() -> Dict[str, Optional[Union[bool, int, str]]]:
    return {
        "batteryPresent": False,
        "batteryPercent": None,
        "isCharging": None,
        "batteryStatus": "Unavailable",
        "batterySecsLeft": None,
    }


def get_battery_info(
    *,
    verbose: bool = False,
) -> Dict[str, Optional[Union[bool, int, str]]]:
    if verbose:
        print(f"Checking battery on {platform.system()}...")

    if psutil is not None:
        try:
            battery = psutil.sensors_battery()
            if battery is not None:
                percent = round(battery.percent)
                if verbose:
                    print(
                        f"Battery detected: {percent}% "
                        f"({'Charging' if battery.power_plugged else 'Discharging'})"
                    )
                return {
                    "batteryPresent": True,
                    "batteryPercent": percent,
                    "isCharging": battery.power_plugged,
                    "batteryStatus": "Charging" if battery.power_plugged else "Not charging",
                    "batterySecsLeft": battery.secsleft,
                }
            if verbose:
                print("psutil: No battery detected")
        except Exception as error:
            if verbose:
                print(f"psutil battery read failed: {error}")
    elif verbose:
        print("psutil not available")

    power_root = Path("/sys/class/power_supply")
    if power_root.exists():
        if verbose:
            print("Checking Linux battery...")
        for entry in power_root.iterdir():
            if read_text(entry / "type") != "Battery":
                continue
            percent = read_text(entry / "capacity")
            status = read_text(entry / "status") or "Unknown"
            if percent and percent.isdigit():
                percent_int = int(percent)
                if verbose:
                    print(f"Linux battery: {percent_int}% ({status})")
                return {
                    "batteryPresent": True,
                    "batteryPercent": percent_int,
                    "isCharging": status.lower() == "charging",
                    "batteryStatus": status,
                    "batterySecsLeft": None,
                }

    if verbose:
        print("No battery detected")
    return default_battery_info()


def send_firebase_notification(
    fcm_token: str,
    title: str,
    body: str,
    level: str,
    event_type: str = "battery",
    channel_id: str = "battery_alerts",
    extra_data: Optional[Dict[str, object]] = None,
):
    """Send a Firebase Cloud Messaging notification"""
    if not FIREBASE_AVAILABLE or messaging is None:
        print(f"⚠️  Firebase not available, skipping notification to {fcm_token[:20]}...")
        return False
        
    try:
        payload_data = {
            'type': event_type,
            'title': title,
            'body': body,
            'level': level,
        }
        if extra_data:
            payload_data.update(
                {
                    str(key): str(value)
                    for key, value in extra_data.items()
                    if value is not None
                }
            )

        message = messaging.Message(
            data=payload_data,
            notification=messaging.Notification(
                title=title,
                body=body,
            ),
            android=messaging.AndroidConfig(
                priority="high",
                notification=messaging.AndroidNotification(
                    channel_id=channel_id,
                    sound="default",
                ),
            ),
            token=fcm_token,
        )
        
        response = messaging.send(message)
        print(f'✅ Firebase notification sent to {fcm_token[:20]}...: {response}')
        return True
    except Exception as e:
        print(f'❌ Firebase notification failed: {e}')
        return False


# ---------------------------------------------------------------------------
# Source-aware log line parsers
# ---------------------------------------------------------------------------

# Nginx / Apache Combined Log Format:
# 1.2.3.4 - frank [10/Oct/2000:13:55:36 -0700] "GET /index.html HTTP/1.1" 200 2326 "ref" "ua"
_COMBINED_LOG_RE = re.compile(
    r'(?P<ip>\S+)\s+\S+\s+\S+\s+'
    r'\[(?P<time>[^\]]+)\]\s+'
    r'"(?P<method>\S+)\s+(?P<path>\S+)\s+\S+"\s+'
    r'(?P<status>\d{3})\s+'
    r'(?P<bytes>\d+|-)'
    r'(?:\s+"(?P<referrer>[^"]*)")?'
    r'(?:\s+"(?P<ua>[^"]*)")?'
)

# UFW kernel log line:
# May  1 10:20:30 hostname kernel: [12345.678] [UFW BLOCK] IN=eth0 OUT= ... SRC=1.2.3.4 DST=5.6.7.8 ... PROTO=TCP SPT=44321 DPT=22
_UFW_RE = re.compile(
    r'(?:SRC=(?P<src>[\d.:a-fA-F]+))?'
    r'(?:.*?DST=(?P<dst>[\d.:a-fA-F]+))?'
    r'(?:.*?PROTO=(?P<proto>\w+))?'
    r'(?:.*?SPT=(?P<spt>\d+))?'
    r'(?:.*?DPT=(?P<dpt>\d+))?'
    r'(?:.*?\[UFW\s+(?P<action>\w+)\])?',
    re.DOTALL,
)

# Generic syslog: "May  1 10:20:30 host proc[123]: message"
_SYSLOG_TS_RE = re.compile(
    r'^(?P<month>\w{3})\s+(?P<day>\d{1,2})\s+(?P<time>\d{2}:\d{2}:\d{2})\s+'
    r'(?P<host>\S+)\s+'
    r'(?P<proc>\S+?)(?:\[\d+\])?:\s*'
    r'(?P<msg>.*)$'
)

# ISO 8601 timestamp (systemd journal format)
_ISO_TS_RE = re.compile(
    r'(?P<ts>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:[+\-]\d{2}:\d{2})?)',
)

# dpkg: "2024-01-01 12:00:00 status installed pkg:amd64 1.2.3"
_DPKG_RE = re.compile(
    r'^(?P<ts>\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})\s+'
    r'(?P<action>\S+)\s+'
    r'(?P<pkg>\S+)'
)

# Generic IP anywhere in line
_IP_RE = re.compile(r'\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b')


def _syslog_ts_to_iso(month: str, day: str, time_str: str) -> str:
    """Convert syslog-style timestamp to ISO8601, assuming current year."""
    try:
        parsed = datetime.strptime(
            f"{datetime.now().year} {month} {int(day):02d} {time_str}",
            "%Y %b %d %H:%M:%S",
        )
        return parsed.replace(tzinfo=timezone.utc).isoformat()
    except ValueError:
        return iso_now()


def _parse_nginx_line(line: str, source: str) -> Optional[Dict[str, Any]]:
    """Parse an nginx or Apache combined-format access log line."""
    m = _COMBINED_LOG_RE.match(line.strip())
    if not m:
        return None

    ip = m.group("ip")
    time_str = m.group("time")  # e.g. 10/Oct/2000:13:55:36 -0700
    http_method = m.group("method")
    path = m.group("path")
    status_code = int(m.group("status"))
    byte_count = m.group("bytes")
    ua = m.group("ua") or ""

    # Parse timestamp
    try:
        ts = datetime.strptime(time_str, "%d/%b/%Y:%H:%M:%S %z").isoformat()
    except ValueError:
        ts = iso_now()

    response_size = 0
    if byte_count and byte_count != "-":
        response_size = int(byte_count)

    return {
        "ipAddress":          ip,
        "timestamp":          ts,
        "method":             http_method,
        "requestMethod":      http_method,
        "request":            f"{http_method} {path}",
        "status":             str(status_code),
        "bytes":              str(response_size),
        "userAgent":          ua,
        "parameters":         source,
        "url":                path,
        "responseCode":       status_code,
        "responseSize":       response_size,
        "country":            "",
        "latitude":           None,
        "longitude":          None,
        "requestRateAnomaly": False,
    }


def _parse_ufw_line(line: str, source: str) -> Optional[Dict[str, Any]]:
    """Parse a UFW kernel log line (ufw.log)."""
    if "[UFW" not in line:
        return None

    # Extract syslog header for timestamp
    line = line.strip()
    ts = iso_now()
    syslog_m = _SYSLOG_TS_RE.match(line)
    if syslog_m:
        ts = _syslog_ts_to_iso(
            syslog_m.group("month"),
            syslog_m.group("day"),
            syslog_m.group("time"),
        )
    else:
        iso_m = _ISO_TS_RE.search(line)
        if iso_m:
            ts = iso_m.group("ts")

    ufw_m = _UFW_RE.search(line)
    src_ip = (ufw_m and ufw_m.group("src")) or "0.0.0.0"
    dst_ip = (ufw_m and ufw_m.group("dst")) or "0.0.0.0"
    proto  = (ufw_m and ufw_m.group("proto")) or "TCP"
    dpt    = (ufw_m and ufw_m.group("dpt"))
    action = (ufw_m and ufw_m.group("action")) or "BLOCK"

    try:
        dst_port = int(dpt) if dpt else 0
    except ValueError:
        dst_port = 0

    return {
        "ipAddress":          src_ip,
        "timestamp":          ts,
        "method":             f"UFW {action}",
        "requestMethod":      proto,
        "request":            line,
        "status":             action,
        "bytes":              str(len(line)),
        "userAgent":          "",
        "parameters":         source,
        "url":                f"ufw://{dst_ip}:{dst_port}",
        "responseCode":       0,
        "responseSize":       len(line),
        "country":            "",
        "latitude":           None,
        "longitude":          None,
        "requestRateAnomaly": False,
    }


def _parse_dpkg_line(line: str, source: str) -> Optional[Dict[str, Any]]:
    """Parse a dpkg.log line."""
    m = _DPKG_RE.match(line.strip())
    if not m:
        return None

    try:
        ts = datetime.strptime(m.group("ts"), "%Y-%m-%d %H:%M:%S")\
               .replace(tzinfo=timezone.utc).isoformat()
    except ValueError:
        ts = iso_now()

    action = m.group("action")
    pkg    = m.group("pkg")
    severity = "INFO"
    if action in ("half-installed", "half-configured", "triggers-pending"):
        severity = "WARN"

    return {
        "ipAddress":          "127.0.0.1",
        "timestamp":          ts,
        "method":             action.upper(),
        "requestMethod":      action.upper(),
        "request":            line.strip(),
        "status":             severity,
        "bytes":              str(len(line)),
        "userAgent":          "",
        "parameters":         source,
        "url":                f"dpkg://{pkg}",
        "responseCode":       0,
        "responseSize":       len(line),
        "country":            "",
        "latitude":           None,
        "longitude":          None,
        "requestRateAnomaly": False,
    }

recent_ssh_attempts = []

def _parse_syslog_line(line: str, source: str) -> Optional[Dict[str, Any]]:
    """Parse a standard syslog/auth/kern/messages line."""
    line = line.strip()
    if not line:
        return None

    ts = iso_now()
    process = source

    syslog_m = _SYSLOG_TS_RE.match(line)
    if syslog_m:
        ts = _syslog_ts_to_iso(
            syslog_m.group("month"),
            syslog_m.group("day"),
            syslog_m.group("time"),
        )
        process = syslog_m.group("proc").rstrip(":")
    else:
        iso_m = _ISO_TS_RE.search(line)
        if iso_m:
            ts = iso_m.group("ts")
        proc_m = re.search(r'(\w+)\[?\d*\]?:', line)
        if proc_m:
            process = proc_m.group(1)

    ips = _IP_RE.findall(line)
    src_ip = ips[0] if ips else "0.0.0.0"

    severity = "INFO"
    lower = line.lower()
    if "critical" in lower or "crit" in lower:
        severity = "CRITICAL"
    elif "error" in lower or "fail" in lower:
        severity = "ERROR"
    elif "warning" in lower or "warn" in lower:
        severity = "WARN"
    elif "debug" in lower:
        severity = "DEBUG"

    global recent_ssh_attempts
    if "sshd" in process:
        ssh_status = None
        ssh_user = "unknown"
        if "failed password" in lower or "invalid user" in lower or "disconnected from invalid user" in lower:
            ssh_status = "FAILED"
            m = re.search(r'user (\S+) from', line) or re.search(r'for (\S+) from', line)
            if m:
                ssh_user = m.group(1)
                if ssh_user == "invalid":
                    m2 = re.search(r'invalid user (\S+) from', line)
                    if m2:
                        ssh_user = m2.group(1)
        elif "accepted " in lower:
            ssh_status = "SUCCESS"
            m = re.search(r'for (\S+) from', line)
            if m:
                ssh_user = m.group(1)

        if ssh_status:
            attempt = {
                "timestamp": ts,
                "ip": src_ip,
                "user": ssh_user,
                "status": ssh_status,
            }
            if not recent_ssh_attempts or recent_ssh_attempts[0] != attempt:
                recent_ssh_attempts.insert(0, attempt)
                recent_ssh_attempts[:] = recent_ssh_attempts[:50]

    return {
        "ipAddress":          src_ip,
        "timestamp":          ts,
        "method":             severity,
        "requestMethod":      severity,
        "request":            line,
        "status":             severity,
        "bytes":              str(len(line)),
        "userAgent":          "",
        "parameters":         source,
        "url":                f"log://{process}/{source}",
        "responseCode":       0,
        "responseSize":       len(line),
        "country":            "",
        "latitude":           None,
        "longitude":          None,
        "requestRateAnomaly": False,
    }


# Source IDs that use the nginx/combined-log format
_COMBINED_FORMAT_SOURCES = {"nginx", "apache"}
# Source IDs that use UFW kernel format
_UFW_SOURCES = {"ufw"}
# Source IDs that use dpkg format
_DPKG_SOURCES = {"dpkg"}


def parse_ubuntu_log_line(line: str, source: str) -> Optional[Dict[str, Any]]:
    """Route to the correct parser based on source, then fall back to syslog."""
    stripped = line.strip()
    if not stripped:
        return None

    # Handle Caddy/JSON logs
    if stripped.startswith("{") and stripped.endswith("}"):
        try:
            import json
            import time
            from datetime import datetime
            data = json.loads(stripped)
            # Extract common fields from Caddy/structured JSON
            req = data.get("request", {})
            remote_ip = req.get("remote_ip", data.get("remote_ip", ""))
            if ":" in remote_ip: # remove port if present
                remote_ip = remote_ip.split(":")[0]
            
            # Use X-Forwarded-For if available in the JSON headers
            headers = req.get("headers", {})
            if "X-Forwarded-For" in headers:
                remote_ip = headers["X-Forwarded-For"][0]
            elif "Cf-Connecting-Ip" in headers:
                remote_ip = headers["Cf-Connecting-Ip"][0]

            return {
                "timestamp": datetime.fromtimestamp(data.get("ts", time.time())).isoformat(),
                "source": source,
                "sourceIp": remote_ip,
                "method": req.get("method", ""),
                "url": req.get("uri", data.get("uri", "")),
                "status": data.get("status", 0),
                "userAgent": headers.get("User-Agent", [""])[0],
                "message": data.get("msg", ""),
                "data": stripped
            }
        except Exception:
            pass

    if source in _COMBINED_FORMAT_SOURCES:
        result = _parse_nginx_line(line, source)
        if result:
            return result
        # Fall through to generic syslog (e.g. nginx error log lines)

    if source in _UFW_SOURCES:
        result = _parse_ufw_line(line, source)
        if result:
            return result
        return None  # skip non-UFW lines in ufw.log

    if source in _DPKG_SOURCES:
        return _parse_dpkg_line(line, source)

    return _parse_syslog_line(line, source)


class LogWatcher:
    """Watch Ubuntu log files and emit parsed entries."""
    
    def __init__(self, log_paths: Optional[list] = None):
        if log_paths is None:
            log_paths = list(SERVER_LOG_SOURCE_PATHS.values())

        self.log_paths = {path: 0 for path in log_paths if Path(path).exists()}
        self.tasks = {}
        self._stop_event = threading.Event()

    
    async def watch_file(self, file_path: str, callback):
        """Watch a log file for new entries."""
        path = Path(file_path)
        if not path.exists():
            return
        
        file_size = path.stat().st_size
        last_pos = self.log_paths.get(file_path, 0)
        source = next((k for k, v in SERVER_LOG_SOURCE_PATHS.items() if v == file_path), path.stem)

        if last_pos == 0 and file_size > 0:
            for line in self.read_recent_lines(path, limit=250):
                parsed = parse_ubuntu_log_line(line, source)
                if parsed:
                    await callback(parsed)
            last_pos = file_size
            self.log_paths[file_path] = last_pos
        
        while not self._stop_event.is_set():
            try:
                await asyncio.sleep(1.0)
                
                if not path.exists():
                    continue
                
                current_size = path.stat().st_size
                
                # File was rotated
                if current_size < last_pos:
                    last_pos = 0
                
                if current_size > last_pos:
                    with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
                        f.seek(last_pos)
                        new_lines = f.readlines()
                        last_pos = f.tell()
                        self.log_paths[file_path] = last_pos
                        
                        for line in new_lines[-100:]:  # Keep last 100 lines
                            parsed = parse_ubuntu_log_line(line, source)
                            if parsed:
                                await callback(parsed)
            
            except Exception as e:
                print(f"Error watching {file_path}: {e}")
                await asyncio.sleep(2.0)
    
    def start_watchers(self, callback, loop):
        """Start watching all log files."""
        for log_path in self.log_paths:
            task = asyncio.run_coroutine_threadsafe(
                self.watch_file(log_path, callback),
                loop
            )
            self.tasks[log_path] = task

    def stop(self):
        """Stop all log watchers."""
        self._stop_event.set()
        for task in self.tasks.values():
            task.cancel()

    @staticmethod
    def read_recent_lines(path: Path, limit: int = 250) -> list[str]:
        try:
            with path.open("r", encoding="utf-8", errors="ignore") as handle:
                lines = handle.readlines()
        except OSError:
            return []
        return [line for line in lines[-limit:] if line.strip()]


class PacketServer:
    def __init__(
        self,
        host: str,
        port: int,
        http_port: int,
        port_retries: int,
        interface: Optional[str],
        status_interval: float,
        bpf_filter: Optional[str],
        enable_logs: bool = False,
        log_paths: Optional[list] = None,
        no_packet_sniffing: bool = False,
        battery_interval: float = 30.0,
        app_token: str = DEFAULT_APP_ACCESS_TOKEN,
    ) -> None:
        self.host = host
        self.port = port
        self.http_port = max(http_port, 0)
        self.port_retries = max(port_retries, 0)
        self.interface = interface
        self.status_interval = status_interval
        self.bpf_filter = bpf_filter
        self.loop: Optional[asyncio.AbstractEventLoop] = None
        self.active_clients: list[dict] = []
        self.no_packet_sniffing = no_packet_sniffing
        self.sniffer: Optional[AsyncSniffer] = None
        self.http_server: Optional[asyncio.AbstractServer] = None
        self.raw_packets_seen = 0
        self.packets_captured = 0
        self.tcp_packets = 0
        self.udp_packets = 0
        self.other_packets = 0
        self.last_packet_at: Optional[str] = None
        self.last_packet_summary: Optional[str] = None
        self.packet_callback_errors = 0
        self.last_packet_error: Optional[str] = None
        self.enable_logs = enable_logs
        self.app_token = app_token.strip()
        self.log_watcher: Optional[LogWatcher] = None
        self.logs_processed = 0
        self.auth_nonces: Dict[str, float] = {}

        # FCM tokens for push notifications
        self.fcm_tokens: Set[str] = load_registered_fcm_tokens()
        self.threat_notification_cooldowns: Dict[str, float] = {}
        
        # Registered devices
        global registered_devices
        registered_devices = load_registered_devices()
        
        # new metrics
        self._seen_src_ips: Set[str] = set()
        self.ssh_connections = 0           # tracked via psutil
        self.active_tcp_connections = 0
        self.udp_connections = 0
        self.unique_source_ips = 0
        
        # Battery notification flags
        self.low_battery_notified = False
        self.high_battery_notified = False
        
        # Battery monitoring interval (less frequent than status updates)
        self.unique_source_ips = 0
        self.ssh_connections = 0
        self.active_tcp_connections = 0
        self.udp_connections = 0
        self.battery_check_interval = battery_interval
        self.cached_battery_info = default_battery_info()
        self.packet_processing_queue: queue.Queue[Optional[Dict[str, object]]] = (
            queue.Queue(maxsize=4096)
        )
        self.packet_processing_drops = 0
        self.packet_worker_stop = threading.Event()
        self.packet_worker = threading.Thread(
            target=self._packet_processing_worker,
            name="packet-processing-worker",
            daemon=True,
        )
        self.telegram_command_stop = threading.Event()
        self.telegram_command_thread: Optional[threading.Thread] = None
        
        if enable_logs:
            self.log_watcher = LogWatcher(log_paths)

        if self.fcm_tokens:
            print(f"Loaded {len(self.fcm_tokens)} registered FCM token(s)")

        self.ws_history_rate_limits: Dict[str, list[float]] = {}
        self.server_memory_mb = 0.0
        self.is_memory_critical = False
        self.is_memory_warning = False

    def iter_candidate_ports(self) -> list[int]:
        if self.port == 0:
            return [0]
        max_port = 65535
        last_port = min(self.port + self.port_retries, max_port)
        return list(range(self.port, last_port + 1))

    def start_sniffer_manually(self) -> bool:
        """Start the sniffer dynamically from the UI."""
        if self.sniffer is not None:
            return True
            
        try:
            capture_interface = self.resolve_capture_interface()
            self.sniffer = AsyncSniffer(
                prn=self.packet_callback,
                store=False,
                iface=capture_interface,
                filter=self.bpf_filter,
                promisc=True,
                started_callback=self._on_sniffer_started,
            )
            self.sniffer.start()
            print("✅ Packet sniffing STARTED manually")
            return True
        except Exception as e:
            print(f"❌ Failed to start sniffer: {e}")
            self.sniffer = None
            return False

    def stop_sniffer_manually(self):
        """Stop the sniffer dynamically."""
        if self.sniffer:
            self.stop_sniffer_safely()
            self.sniffer = None
            print("🛑 Packet sniffing STOPPED manually")

    def stop_sniffer_safely(self) -> None:
        if self.sniffer is None:
            return

        try:
            if getattr(self.sniffer, "running", False):
                self.sniffer.stop()
        except PermissionError as error:
            print(f"⚠️  Packet sniffing shutdown ignored a permission error: {error}")
        except Exception as error:
            print(f"⚠️  Packet sniffing shutdown failed: {error}")
        finally:
            self.sniffer = None

    def resolve_capture_interface(self) -> Optional[str]:
        if self.interface:
            return self.interface
        if platform.system() == "Linux":
            # Match `tcpdump -i any` when no explicit interface is configured.
            return "any"
        return None

    def _on_sniffer_started(self) -> None:
        print("Packet sniffer thread is running.")

    def refresh_battery_info(self) -> Dict[str, Optional[Union[bool, int, str]]]:
        self.cached_battery_info = get_battery_info()
        return self.cached_battery_info

    def _enqueue_packet_payload(self, packet_payload: Dict[str, object]) -> None:
        try:
            self.packet_processing_queue.put_nowait(packet_payload)
        except queue.Full:
            self.packet_processing_drops += 1
            self.last_packet_error = "Packet processing queue is full; dropping payload."

    def _packet_processing_worker(self) -> None:
        while not self.packet_worker_stop.is_set():
            try:
                packet_payload = self.packet_processing_queue.get(timeout=0.5)
            except queue.Empty:
                continue

            if packet_payload is None:
                self.packet_processing_queue.task_done()
                break

            try:
                self._process_packet_payload(packet_payload)
            except Exception as error:
                self.packet_callback_errors += 1
                self.last_packet_error = str(error)
                print(f"Packet processing worker failed: {error}")
            finally:
                self.packet_processing_queue.task_done()

    def _process_packet_payload(self, packet_payload: Dict[str, object]) -> None:
        src = packet_payload.get("srcIp") or packet_payload.get("ipAddress")
        if isinstance(src, str):
            geo_info = get_geoip(src)
            if geo_info:
                packet_payload.update(geo_info)

        alerts = analyze_for_threats(packet_payload)
        if alerts:
            packet_payload["alerts"]        = alerts
            packet_payload["threatLevel"]   = determine_threat_level(alerts)
            packet_payload["severityScore"] = _compute_severity_score(alerts)
            
            # Embed real-time cumulative reputation score
            rep_info = ip_reputation.get(src, {"score": 0.0})
            packet_payload["reputationScore"] = round(rep_info["score"], 1)
            
            self.maybe_send_threat_notification(packet_payload, alerts, "packet")

        # Sanitize everything before DB/broadcast to prevent injection
        packet_payload = sanitize_log_field(packet_payload)

        try:
            db_queue.put_nowait(
                (
                    packet_payload["timestamp"],
                    "packet",
                    src,
                    json.dumps(packet_payload),
                )
            )
        except queue.Full:
            print("WARNING: SQLite db_queue is full, dropping packet event to prevent memory overflow")

        if self.loop is not None:
            asyncio.run_coroutine_threadsafe(
                self.broadcast_json(packet_payload),
                self.loop,
            )

    async def memory_monitor_loop(self) -> None:
        """Monitor memory usage and perform aggressive cleanup or refuse services if high."""
        print("Memory monitor loop started.")
        while True:
            try:
                # Get memory usage of the current process
                process = psutil.Process(os.getpid())
                mem_bytes = process.memory_info().rss
                self.server_memory_mb = mem_bytes / (1024 * 1024)
                
                self.is_memory_warning = self.server_memory_mb > SOFT_MEMORY_LIMIT_MB
                self.is_memory_critical = self.server_memory_mb > HARD_MEMORY_LIMIT_MB
                
                # Broadcast memory status to all clients
                warning_payload = {
                    "type": "server_warning",
                    "category": "resource_usage",
                    "memory_mb": round(self.server_memory_mb, 1),
                    "is_critical": self.is_memory_critical,
                    "is_warning": self.is_memory_warning,
                    "message": None
                }
                
                if self.is_memory_warning:
                    # Aggressive cleanup
                    self._perform_aggressive_cleanup()
                    warning_payload["message"] = f"⚠️ High memory usage: {round(self.server_memory_mb, 1)}MB. Cleaning up caches."
                    
                if self.is_memory_critical:
                    # Refuse services or notify
                    warning_payload["message"] = f"🚨 CRITICAL: Service restricted due to high memory ({round(self.server_memory_mb, 1)}MB)."
                    
                    # Level 1: Stop Sniffer (4GB+)
                    if self.server_memory_mb > CRITICAL_MEMORY_LIMIT_MB:
                        if self.sniffer:
                            print(f"🛑 EMERGENCY SHUTDOWN: Stopping sniffer (Memory: {round(self.server_memory_mb, 1)}MB)")
                            self.stop_sniffer_manually()
                            warning_payload["message"] = "🛑 EMERGENCY: Sniffer stopped to save memory."
                    
                    # Level 2: Stop Log Watcher (3.5GB+)
                    if self.server_memory_mb > 3500:
                        if self.log_watcher:
                            print(f"🛑 EMERGENCY SHUTDOWN: Stopping log watcher (Memory: {round(self.server_memory_mb, 1)}MB)")
                            self.log_watcher.stop()
                            self.log_watcher = None
                            warning_payload["message"] = "🛑 EMERGENCY: Log watcher stopped to save memory."
                
                if self.is_memory_warning or self.is_memory_critical:
                    await self.broadcast_json(warning_payload)
                else:
                    # Send clear status if we were previously in warning
                    await self.broadcast_json(warning_payload)
                
            except Exception as e:
                print(f"Memory monitor error: {e}")
            
            await asyncio.sleep(10) # Check every 10 seconds

    def _perform_aggressive_cleanup(self) -> None:
        """Clear large non-essential caches to save memory."""
        cleared = False
        # 1. Clear GeoIP cache if it's large
        if len(geoip_cache) > 500:
            geoip_cache.clear()
            cleared = True
        
        # 2. Clear reputation info for low-risk IPs
        keys_to_del = [ip for ip, data in ip_reputation.items() if data.get("score", 0) < 10.0]
        if len(keys_to_del) > 100:
            for ip in keys_to_del:
                del ip_reputation[ip]
            cleared = True
            
        # 3. Clear port scan tracker
        if port_scan_tracker:
            port_scan_tracker.clear()
            cleared = True
        
        # 4. Drop packet queue if it's getting large
        while self.packet_processing_queue.qsize() > 500:
            try:
                self.packet_processing_queue.get_nowait()
                self.packet_processing_drops += 1
                cleared = True
            except:
                break
        
        if cleared:
            print(f"Aggressive memory cleanup performed at {round(self.server_memory_mb, 1)}MB")

    def clear_server_database(self) -> None:
        """Clear the events table in the server database to save space."""
        try:
            # We use the existing db_queue to ensure thread-safety if possible, 
            # but for a full purge a direct connection is cleaner.
            conn = sqlite3.connect("firewall_insane.db")
            cursor = conn.cursor()
            cursor.execute("DELETE FROM events")
            conn.commit()
            conn.close()
            print("🧹 Server database CLEARED (No active clients).")
        except Exception as e:
            print(f"Error clearing server database: {e}")

    def _extract_auth_params(self, target: str, headers: Optional[Dict[str, str]]) -> tuple[str, str, str, str]:
        headers = headers or {}
        timestamp = headers.get("x-app-timestamp", "").strip()
        nonce = headers.get("x-app-nonce", "").strip()
        signature = headers.get("x-app-signature", "").strip()
        device_id = headers.get("x-device-id", "").strip()
        
        if not timestamp or not nonce or not signature:
            query = parse_qs(urlsplit(target).query)
            timestamp = timestamp or query.get("app_timestamp", [""])[0].strip()
            nonce = nonce or query.get("app_nonce", [""])[0].strip()
            signature = signature or query.get("app_signature", [""])[0].strip()
            device_id = device_id or query.get("device_id", [""])[0].strip()
            
        return timestamp, nonce, signature, device_id

    def is_authorized_app_request(
        self,
        target: str,
        headers: Optional[Dict[str, str]] = None,
    ) -> Union[bool, str]:
        if not self.app_token:
            return True

        timestamp_str, nonce, signature, device_id = self._extract_auth_params(target, headers)
        if not timestamp_str or not nonce or not signature:
            return False

        now = time.time()
        self.auth_nonces = {n: t for n, t in self.auth_nonces.items() if now - t <= 60.0}

        try:
            timestamp = float(timestamp_str)
        except ValueError:
            print(f"DEBUG Auth: Invalid timestamp {timestamp_str}")
            return False

        if abs(now - timestamp) > 60.0:
            print(f"DEBUG Auth: Clock drift. Now={now}, Ts={timestamp}, Diff={abs(now-timestamp)}")
            return False

        if nonce in self.auth_nonces:
            print(f"DEBUG Auth: Replayed nonce {nonce}")
            return False

        path = urlsplit(target).path
        if path == "/":
            path = ""
        # Payload includes device_id if provided by the client
        payload = f"GET:{path}::{timestamp_str}:{nonce}{':' + device_id if device_id else ''}"
        expected_sig = hmac.new(
            self.app_token.encode("utf-8"),
            payload.encode("utf-8"),
            "sha256"
        ).hexdigest()

        if hmac.compare_digest(signature, expected_sig):
            self.auth_nonces[nonce] = now
            return device_id if device_id else True
            
        return False

    @staticmethod
    def parse_http_headers(request_data: bytes) -> Dict[str, str]:
        header_lines = request_data.decode("latin-1", errors="replace").split("\r\n")[1:]
        headers: Dict[str, str] = {}
        for line in header_lines:
            if not line or ":" not in line:
                continue
            name, value = line.split(":", 1)
            headers[name.strip().lower()] = value.strip()
        return headers

    def register_fcm_token(self, raw_token: object, device_id: str) -> bool:
        token = normalize_fcm_token(raw_token)
        if token is None:
            return False

        # Bind token to specific device for targeted/verified alerts
        if device_id in registered_devices:
            registered_devices[device_id]['fcm_token'] = token
            save_registered_devices(registered_devices)

        is_new_token = token not in self.fcm_tokens
        self.fcm_tokens.add(token)
        if is_new_token:
            save_registered_fcm_tokens(self.fcm_tokens)
            print(f"Registered FCM token for device {device_id[:8]}: {token[:20]}...")
        return True

    def maybe_send_threat_notification(
        self,
        payload: Dict[str, object],
        alerts: list[str],
        source_type: str,
    ) -> None:
        if not alerts:
            return

        title, body, extra_data = build_threat_notification(payload, alerts, source_type)
        cooldown_key = "|".join(
            (
                source_type,
                extra_data.get("source_ip", "unknown"),
                extra_data.get("alerts", ""),
            )
        )
        now = time.time()
        last_sent = self.threat_notification_cooldowns.get(cooldown_key, 0.0)
        if now - last_sent < THREAT_NOTIFICATION_COOLDOWN_SECONDS:
            return

        self.threat_notification_cooldowns[cooldown_key] = now
        level = extra_data.get("level", "high")
        print(f"Threat notification queued: {title} [{level}]")

        if TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID:
            queue_alert(build_telegram_alert_message(payload, alerts, source_type))

        fcm_title = f"{str(level).title()} threat detected"
        fcm_body = "Anomaly detected. Please check the Telegram alert bot."
        fcm_extra_data = dict(extra_data)
        fcm_extra_data["title"] = fcm_title
        fcm_extra_data["body"] = fcm_body

        # Security Hardening: Only send to tokens bound to VERIFIED devices
        target_tokens = set()
        for dev_id, dev_info in registered_devices.items():
            if dev_info.get('is_verified') and dev_info.get('fcm_token'):
                target_tokens.add(dev_info['fcm_token'])
        
        if not target_tokens and not registered_devices:
            # Fallback for manual registration / migration
            target_tokens = self.fcm_tokens

        for token in target_tokens:
            send_firebase_notification(
                token,
                fcm_title,
                fcm_body,
                str(level),
                event_type="security_alert",
                channel_id="security_alerts",
                extra_data=fcm_extra_data,
            )

    def build_http_response(
        self,
        status_code: int,
        body: Union[str, bytes],
        content_type: str = "text/plain; charset=utf-8",
    ) -> bytes:
        reason = {
            200: "OK",
            401: "Unauthorized",
            400: "Bad Request",
            404: "Not Found",
            405: "Method Not Allowed",
            500: "Internal Server Error",
        }.get(status_code, "OK")
        payload = body.encode("utf-8") if isinstance(body, str) else body
        headers = [
            f"HTTP/1.1 {status_code} {reason}",
            f"Content-Type: {content_type}",
            f"Content-Length: {len(payload)}",
            "Connection: close",
            "",
            "",
        ]
        return "\r\n".join(headers).encode("utf-8") + payload

    async def handle_http_client(
        self,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
    ) -> None:
        status_code = 200
        try:
            request_data = await asyncio.wait_for(reader.readuntil(b"\r\n\r\n"), timeout=5)
            request_line = request_data.split(b"\r\n", 1)[0].decode("latin-1", errors="replace")
            headers = self.parse_http_headers(request_data)
            parts = request_line.split()
            if len(parts) != 3:
                response = self.build_http_response(400, "Invalid HTTP request\n")
                status_code = 400
            if parts:
                method, target, _version = parts
                path = urlsplit(target).path or "/"
                
                if method != "GET":
                    response = self.build_http_response(405, "Only GET is supported\n")
                    status_code = 405
                elif path in {"/", "/health", "/healthz"}:
                    if not self.is_authorized_app_request(target, headers):
                        status_code = 401
                        response = self.build_http_response(
                            401,
                            "Unauthorized. Application Only.\n",
                        )
                    else:
                        body = json.dumps(
                            {
                                "status": "running",
                                "websocket_port": self.port,
                                "http_port": self.http_port,
                                "local_ip": get_local_ip(),
                            },
                            indent=2,
                        ) + "\n"
                        response = self.build_http_response(
                            200,
                            body,
                            content_type="application/json; charset=utf-8",
                        )
                elif path == "/status":
                    if not self.is_authorized_app_request(target, headers):
                        status_code = 401
                        response = self.build_http_response(
                            401,
                            "Unauthorized. Application Only.\n",
                        )
                    else:
                        body = json.dumps(self.build_status_payload(), indent=2) + "\n"
                        response = self.build_http_response(
                            200,
                            body,
                            content_type="application/json; charset=utf-8",
                        )
                else:
                    response = self.build_http_response(404, "Not found\n")
                    status_code = 404

            writer.write(response)
            await writer.drain()
        except asyncio.IncompleteReadError:
            status_code = 400
        except asyncio.TimeoutError:
            status_code = 400
        except Exception as error:
            status_code = 500
            with contextlib.suppress(Exception):
                writer.write(self.build_http_response(500, f"Server error: {error}\n"))
                await writer.drain()
        finally:
            peer = writer.get_extra_info("peername")
            if status_code >= 400 and peer is not None:
                print(f"HTTP {status_code} from {peer}")
            writer.close()
            with contextlib.suppress(Exception):
                await writer.wait_closed()

    async def start_http_server(self) -> None:
        if self.http_port == 0:
            return

        self.http_server = await asyncio.start_server(
            self.handle_http_client,
            self.host,
            self.http_port,
        )
        bound_port = self.http_port
        if self.http_server.sockets:
            socket_name = self.http_server.sockets[0].getsockname()
            if isinstance(socket_name, tuple) and len(socket_name) >= 2:
                bound_port = int(socket_name[1])
        self.http_port = bound_port
        print(f"HTTP status server running on http://{self.host}:{self.http_port}")
        if self.host in {"0.0.0.0", "::"}:
            print(
                f"HTTP status available from another device at http://{get_local_ip()}:{self.http_port}"
            )

    def process_websocket_request(self, *args) -> Optional[tuple]:
        """Handshake hook to authorize WebSocket connections."""
        # Modern signature: (connection, request)
        # Legacy signature: (path, headers)
        is_modern = len(args) == 2 and not isinstance(args[0], str)
        
        peer = "unknown"
        if is_modern:
            _connection, request = args
            path = request.path
            headers_obj = request.headers
            # Try to get peer IP for logging
            try:
                peer = _connection.remote_address[0]
            except:
                pass
        elif len(args) == 2:
            path, headers_obj = args
        else:
            return (
                HTTPStatus.BAD_REQUEST,
                [('Content-Type', 'text/plain')],
                b'Invalid handshake signature\n',
            )

        # Normalize headers
        headers = {}
        if hasattr(headers_obj, 'items'):
            headers = {
                str(k).lower(): str(v).strip()
                for k, v in headers_obj.items()
            }
        
        if self.is_authorized_app_request(path, headers):
            return None

        # Rejection: Return Response object for modern asyncio server, or tuple for legacy
        if is_modern and WSResponse is not None:
            return WSResponse(
                status_code=HTTPStatus.UNAUTHORIZED,
                reason_phrase='Unauthorized',
                headers=WSHeaders([('Content-Type', 'text/plain; charset=utf-8')]) if WSHeaders else [('Content-Type', 'text/plain; charset=utf-8')],
                body=b'Unauthorized. Application Only.\n',
            )

        return (
            HTTPStatus.UNAUTHORIZED,
            [('Content-Type', 'text/plain; charset=utf-8')],
            b'Unauthorized. Application Only.\n',
        )

    async def start(self) -> None:
        self.loop = asyncio.get_running_loop()
        self._refresh_connection_metrics()
        self.refresh_battery_info()
        if not self.packet_worker.is_alive():
            self.packet_worker.start()
        if self.app_token:
            print("App token protection enabled for /status and WebSocket access.")
        if TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID:
            print(f"Telegram alerts enabled for chat {TELEGRAM_CHAT_ID}.")
            if self.telegram_command_thread is None:
                self.telegram_command_thread = threading.Thread(
                    target=telegram_command_worker,
                    args=(self.telegram_command_stop,),
                    name="telegram-command-worker",
                    daemon=True,
                )
                self.telegram_command_thread.start()
        else:
            print("Telegram alerts disabled; bot token or chat id is missing.")
        
        # Try to start packet sniffer (requires root on Linux)
        if self.no_packet_sniffing:
            print("ℹ️  Packet sniffing disabled by --no-packet-sniffing flag")
            self.sniffer = None
        else:
            try:
                capture_interface = self.resolve_capture_interface()
                self.sniffer = AsyncSniffer(
                    prn=self.packet_callback,
                    store=False,
                    iface=capture_interface,
                    filter=self.bpf_filter,
                    promisc=True,
                    started_callback=self._on_sniffer_started,
                )
                self.sniffer.start()
                if capture_interface:
                    print(f"Capture interface resolved to: {capture_interface}")
                print("✅ Packet sniffing enabled")
            except PermissionError as e:
                print(f"⚠️  Packet sniffing disabled (permission denied): {e}")
                self.sniffer = None
            except Exception as e:
                print(f"⚠️  Packet sniffing disabled (error): {e}")
                self.sniffer = None
        
        # Start log watchers if enabled
        if self.enable_logs and self.log_watcher:
            self.log_watcher.start_watchers(self.log_callback, self.loop)

        status_task = asyncio.create_task(self.publish_status_periodically())
        battery_task = asyncio.create_task(self.monitor_battery_periodically())
        memory_task = asyncio.create_task(self.memory_monitor_loop())
        try:
            await self.start_http_server()
            candidate_ports = self.iter_candidate_ports()
            for index, candidate_port in enumerate(candidate_ports):
                try:
                    async with websockets.serve(
                        self.handle_client,
                        self.host,
                        candidate_port,
                        ping_interval=20,
                        ping_timeout=20,
                        max_queue=256,
                        process_request=self.process_websocket_request,
                    ) as websocket_server:
                        bound_port = candidate_port
                        if websocket_server.sockets:
                            socket_name = websocket_server.sockets[0].getsockname()
                            if isinstance(socket_name, tuple) and len(socket_name) >= 2:
                                bound_port = int(socket_name[1])
                        self.port = bound_port
                        print(f"Packet server running on ws://{self.host}:{self.port}")
                        if self.host in {"0.0.0.0", "::"}:
                            print(
                                f"Connect from another device using ws://{get_local_ip()}:{self.port}"
                            )
                        if index > 0:
                            print(
                                f"Port {candidate_ports[0]} was busy, so the server started on {self.port}."
                            )
                        if self.enable_logs:
                            print("Log watching enabled")
                        if self.sniffer is not None:
                            print("Packet sniffing enabled")
                        await asyncio.Future()
                except OSError as error:
                    if not is_address_in_use_error(error):
                        raise
                    if index == len(candidate_ports) - 1:
                        retry_note = ""
                        if self.port_retries > 0:
                            retry_note = (
                                f" after trying ports {candidate_ports[0]}-{candidate_ports[-1]}"
                            )
                        raise OSError(
                            error.errno,
                            f"Could not start WebSocket server on {self.host}:{candidate_port}"
                            f"{retry_note}. The address is already in use. "
                            "Stop the conflicting process or start the server with a different "
                            "--port value.",
                        ) from error
                    next_port = candidate_ports[index + 1]
                    print(
                        f"Port {candidate_port} is already in use; trying port {next_port}..."
                    )
        finally:
            status_task.cancel()
            battery_task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await status_task
                await battery_task

            if self.http_server is not None:
                self.http_server.close()
                with contextlib.suppress(Exception):
                    await self.http_server.wait_closed()
                self.http_server = None
            self.packet_worker_stop.set()
            with contextlib.suppress(queue.Full):
                self.packet_processing_queue.put_nowait(None)
            if self.packet_worker.is_alive():
                self.packet_worker.join(timeout=2.0)
            self.telegram_command_stop.set()
            if (
                self.telegram_command_thread is not None
                and self.telegram_command_thread.is_alive()
            ):
                self.telegram_command_thread.join(timeout=2.0)
            self.stop_sniffer_safely()

    async def handle_client(self, websocket: Any) -> None:
        remote = getattr(websocket, "remote_address", None)
        ip = remote[0] if isinstance(remote, tuple) else str(remote).split(':')[0] if remote else 'unknown'

        # Re-read the authenticated device id from the handshake request so
        # identity checks continue to work even when auth arrives via query params.
        # Extract headers robustly for both old and new websockets versions
        headers_obj = getattr(websocket, 'request_headers', None)
        if headers_obj is None:
            # Modern websockets (14.0+) stores headers on the request object
            request = getattr(websocket, 'request', None)
            if request:
                headers_obj = getattr(request, 'headers', {})
        
        headers = {str(k).lower(): str(v).strip() for k, v in (headers_obj.items() if hasattr(headers_obj, 'items') else {})}
        request_target = getattr(websocket, "path", None)
        if request_target is None:
            # Modern websockets (14.0+)
            request = getattr(websocket, 'request', None)
            if request:
                request_target = getattr(request, 'path', "")
        request_target = request_target or ""
        _timestamp, _nonce, _signature, handshake_device_id = self._extract_auth_params(
            request_target,
            headers,
        )

        client_info = {
            'websocket': websocket,
            'ip': ip,
            'device_id': handshake_device_id,
            'device': 'Unknown Device',
            'requests': 0,
            'connected_at': iso_now(),
            'last_seen': iso_now(),
        }
        self.active_clients.append(client_info)
        client_label = f"{ip} ({handshake_device_id or 'unknown'})"
        print(f"Client connected: {client_label}")
        await self.send_json(websocket, self.build_status_payload())

        try:
            async for message in websocket:
                client_info['last_seen'] = iso_now()
                client_info['requests'] += 1
                await self.handle_client_message(websocket, message, client_info)
        finally:
            # Mark device as inactive when disconnected
            device_id = client_info.get('device_id')
            if device_id:
                update_device_activity(device_id, False)
            if client_info in self.active_clients:
                self.active_clients.remove(client_info)
            print(f"Client disconnected: {client_label}")
            
            # Auto-clear backend database if no one is watching
            if not self.active_clients:
                self.clear_server_database()

    async def handle_client_message(self, websocket: Any, message: str, client_info: dict) -> None:
        try:
            payload = json.loads(message)
        except json.JSONDecodeError:
            return

        action = str(payload.get("action", "")).lower()
        if action in {"get_status", "status", "refresh"}:
            await self.send_json(websocket, self.build_status_payload())
        elif action == "register_device":
            device_info = payload.get("device", {})
            device_id = device_info.get("deviceId", "").strip()
            
            # Verify that the registered device_id matches the one from the authenticated handshake
            if client_info.get("device_id") and device_id != client_info["device_id"]:
                print(f"❌ Security violation: client at {client_info['ip']} tried to register device_id '{device_id}' but handshake used '{client_info['device_id']}'")
                await self.send_json(websocket, {"type": "error", "message": "Identity mismatch. Device registration failed."})
                return

            if not device_id:
                await self.send_json(websocket, {"type": "error", "message": "deviceId is required."})
                return

            # Update client info with device details
            client_info.update({
                'device_id': device_id,
                'device_name': device_info.get('device', 'Unknown Device'),
                'device_model': device_info.get('model', 'Unknown'),
                'device_manufacturer': device_info.get('manufacturer', 'Unknown'),
                'platform': device_info.get('platform', 'Unknown'),
                'android_version': device_info.get('androidVersion', 'Unknown'),
                'mac_address': device_info.get('macAddress', 'Not Available'),
                'device': device_info.get('device', 'Unknown Device'),
            })
            
            # Register the device (auto-verify if it's the first one)
            is_verified = len(registered_devices) == 0
            register_device(device_id, {
                **device_info,
                'ip': client_info['ip'],
                'device_id': device_id,
                'is_verified': is_verified or registered_devices.get(device_id, {}).get('is_verified', False),
            })
            
            # Mark as active
            update_device_activity(device_id, True)
            
            print(f"Device registered: {device_info.get('name', 'Unknown')} ({device_id}) from {client_info['ip']}")
            await self.send_json(websocket, {"type": "device_registered", "success": True})
        elif action == "get_history":
            history_type = payload.get("history_type", "packet")
            source = payload.get("source")
            print(f"DEBUG: Received history request: {history_type} for source {source}")
            
            # 1. Rate limiting per client IP
            client_ip = client_info['ip']
            now = time.time()
            requests = self.ws_history_rate_limits.get(client_ip, [])
            # Filter out timestamps outside the sliding window
            requests = [t for t in requests if now - t < WS_RATE_LIMIT_WINDOW_SECONDS]
            
            if len(requests) >= WS_RATE_LIMIT_MAX_HISTORY_REQUESTS:
                print(f"⚠️ WebSocket rate limit exceeded for {client_ip} (action: get_history)")
                await self.send_json(websocket, {
                    "type": "error",
                    "message": "Rate limit exceeded for history requests. Please wait a minute."
                })
                return
                
            requests.append(now)
            
            # Prune rate limit map occasionally
            if len(self.ws_history_rate_limits) > 1000:
                self.ws_history_rate_limits = {
                    k: v for k, v in self.ws_history_rate_limits.items() 
                    if now - v[-1] < 3600
                }
                
            self.ws_history_rate_limits[client_ip] = requests

            # 2. Pagination caps
            limit = int(payload.get("limit", 100))
            if limit > MAX_HISTORY_LIMIT:
                limit = MAX_HISTORY_LIMIT
            elif limit < 1:
                limit = 1
                
            offset = int(payload.get("offset", 0))
            source = str(payload.get("source", "")).strip() or None

            def on_log_chunk(log, count, total):
                # Use call_soon_threadsafe because we're in an executor thread
                self.loop.call_soon_threadsafe(
                    asyncio.create_task,
                    self.send_json(websocket, {
                        "type": "history_progress",
                        "history_type": history_type,
                        "source": source,
                        "progress": count / total if total > 0 else 1.0,
                        "loaded": count,
                        "total": total,
                        "log": log,
                        "is_done": count == total
                    })
                )

            # Fetch history asynchronously
            history = await self.loop.run_in_executor(
                None,
                get_history,
                history_type,
                limit,
                source,
                offset,
                on_log_chunk
            )

            # If no logs were found, send an immediate progress update showing 0/0
            if not history:
                await self.send_json(websocket, {
                    "type": "history_progress",
                    "history_type": history_type,
                    "source": source,
                    "progress": 1.0,
                    "loaded": 0,
                    "total": 0,
                    "is_done": True
                })
                await self.send_json(websocket, {
                    "type": "history_response",
                    "history_type": history_type,
                    "source": source,
                    "offset": offset,
                    "data": history
                })
        elif action == "register_fcm":
            fcm_token = payload.get("fcm_token")
            device_id = client_info.get("device_id")
            
            if not device_id:
                print(f"❌ FCM registration failed: No device_id associated with connection from {client_info['ip']}")
                await self.send_json(websocket, {"type": "fcm_registered", "success": False, "error": "No device identity."})
                return

            if self.register_fcm_token(fcm_token, device_id):
                print(f"📱 Bound FCM token to device {device_id[:10]}...")
                await self.send_json(websocket, {"type": "fcm_registered", "success": True})
            else:
                await self.send_json(websocket, {"type": "fcm_registered", "success": False})
        elif action == "start_sniffing":
            success = self.start_sniffer_manually()
            await self.send_json(websocket, {"type": "sniffing_status", "running": success})
        elif action == "stop_sniffing":
            self.stop_sniffer_manually()
            await self.send_json(websocket, {"type": "sniffing_status", "running": False})

    def packet_callback(self, packet: Any) -> None:
        if self.is_memory_critical:
            return
            
        self.raw_packets_seen += 1
        try:
            packet_payload = self.parse_packet(packet)
            if packet_payload is None or self.loop is None:
                return

            self.packets_captured += 1
            protocol = packet_payload["protocol"]
            if protocol == "TCP":
                self.tcp_packets += 1
            elif protocol == "UDP":
                self.udp_packets += 1
            else:
                self.other_packets += 1

            # track unique source IPs
            src = packet_payload.get("srcIp") or packet_payload.get("ipAddress")
            if src:
                self._seen_src_ips.add(src)
                self.unique_source_ips = len(self._seen_src_ips)

            self.last_packet_at = packet_payload["timestamp"]
            self.last_packet_summary = str(packet_payload.get("data") or "")
            self._enqueue_packet_payload(packet_payload)
        except Exception as error:
            self.packet_callback_errors += 1
            self.last_packet_error = str(error)
            print(
                f"Packet callback failed after raw packet #{self.raw_packets_seen}: "
                f"{error}"
            )

    async def log_callback(self, log_payload: Dict[str, object]) -> None:
        """Callback for processed log entries."""
        if self.loop is None:
            return
        
        self.logs_processed += 1
        
        # Insane Mode Enhancements
        src = log_payload.get("sourceIp") or log_payload.get("ipAddress")
        if src and type(src) == str:
            geo_info = get_geoip(src)
            if geo_info:
                log_payload.update(geo_info)
                
        alerts = analyze_for_threats(log_payload)
        if alerts:
            log_payload["alerts"]        = alerts
            log_payload["threatLevel"]   = determine_threat_level(alerts)
            log_payload["severityScore"] = _compute_severity_score(alerts)
            
            # Embed real-time cumulative reputation score
            rep_info = ip_reputation.get(src, {"score": 0.0})
            log_payload["reputationScore"] = round(rep_info["score"], 1)
            
            self.maybe_send_threat_notification(log_payload, alerts, "log")

        # Sanitize everything before DB/broadcast to prevent injection
        log_payload = sanitize_log_field(log_payload)
            
        try:
            db_queue.put_nowait((log_payload["timestamp"], "log", src, json.dumps(log_payload)))
        except queue.Full:
            print("WARNING: SQLite db_queue is full, dropping log event to prevent memory overflow")
        
        await self.broadcast_json(log_payload)

    def _refresh_connection_metrics(self) -> None:
        # Disabled: psutil.net_connections is very memory intensive on busy servers
        return

    def parse_packet(self, packet: Any) -> Optional[Dict[str, object]]:
        if IP in packet:
            ip_layer = packet[IP]
            ttl = getattr(ip_layer, "ttl", None)
        elif IPv6 in packet:
            ip_layer = packet[IPv6]
            ttl = getattr(ip_layer, "hlim", None)
        else:
            return None
        protocol = "OTHER"
        src_port = None
        dst_port = None

        if TCP in packet:
            protocol = "TCP"
            src_port = packet[TCP].sport
            dst_port = packet[TCP].dport
        elif UDP in packet:
            protocol = "UDP"
            src_port = packet[UDP].sport
            dst_port = packet[UDP].dport

        endpoint = ip_layer.dst if dst_port is None else f"{ip_layer.dst}:{dst_port}"
        raw_packet = (
            f"{protocol} {ip_layer.src}"
            f"{f':{src_port}' if src_port is not None else ''}"
            f" -> {ip_layer.dst}"
            f"{f':{dst_port}' if dst_port is not None else ''}"
            f" ({len(packet)} bytes)"
        )
        summary = packet.summary()

        return {
            "type": "packet",
            "timestamp": iso_now(),
            "srcIp": ip_layer.src,
            "dstIp": ip_layer.dst,
            "sourceIp": ip_layer.src,
            "ipAddress": ip_layer.src,
            "protocol": protocol,
            "srcPort": src_port,
            "dstPort": dst_port,
            "port": dst_port,
            "packetLength": len(packet),
            "ttl": ttl,
            "method": protocol,
            "requestMethod": protocol,
            "status": protocol,
            "statusText": protocol,
            "responseCode": 0,
            "responseSize": len(packet),
            "bytes": str(len(packet)),
            "url": endpoint,
            "raw": raw_packet,
            "data": summary,
            "message": summary,
            "request": summary,
        }

    async def monitor_battery_periodically(self) -> None:
        """Monitor battery levels less frequently than status updates"""
        while True:
            await asyncio.sleep(self.battery_check_interval)
            
            battery_info = self.refresh_battery_info()
            if battery_info.get("batteryPercent") is not None:
                percent = battery_info["batteryPercent"]
                print(f"🔋 Current battery: {percent}%")
                if percent <= 30 and not self.low_battery_notified:
                    print(f"🔋 BATTERY LOW: {percent}% - Sending Firebase notifications")
                    for token in self.fcm_tokens.copy():
                        send_firebase_notification(
                            token, 
                            "Low Battery",
                            f"Battery is {percent}%. Please put it on charge.",
                            "low"
                        )
                    self.low_battery_notified = True
                elif percent > 30:
                    self.low_battery_notified = False
                if percent >= 80 and not self.high_battery_notified:
                    print(f"🔋 BATTERY HIGH: {percent}% - Sending Firebase notifications")
                    for token in self.fcm_tokens.copy():
                        send_firebase_notification(
                            token, 
                            "Battery Charged",
                            f"Battery is {percent}%. Enough battery, you can remove the charge.",
                            "high"
                        )
                    self.high_battery_notified = True
                elif percent < 80:
                    self.high_battery_notified = False

    async def publish_status_periodically(self) -> None:
        while True:
            await asyncio.sleep(self.status_interval)
            self._refresh_connection_metrics()
            payload = self.build_status_payload()
            await self.broadcast_json(payload)

    def get_active_clients_info(self) -> list[dict]:
        clients_info = []
        for client in self.active_clients:
            ip = client.get('ip', 'unknown')
            geo = get_geoip(ip)
            location = f"{geo.get('city', '')}, {geo.get('country', '')}".strip(', ')
            if not location:
                location = 'Unknown'
            
            device_name = client.get('device', 'Unknown Device')
            device_model = client.get('device_model', 'Unknown')
            platform = client.get('platform', 'Unknown')
            android_version = client.get('android_version', 'Unknown')
            mac_address = client.get('mac_address', 'Not Available')
            
            clients_info.append({
                "ip": ip,
                "device": f"{device_name} ({device_model})",
                "deviceName": device_name,
                "deviceModel": device_model,
                "platform": platform,
                "androidVersion": android_version,
                "macAddress": mac_address,
                "location": location,
                "requests": client.get('requests', 0),
                "lastSeen": format_timestamp_to_ist_ddmmyy(client.get('last_seen', '')),
                "connectedAt": format_timestamp_to_ist_ddmmyy(client.get('connected_at', '')),
                "isActive": True,
            })
        return clients_info

    def get_registered_devices_info(self) -> list[dict]:
        unique_devices = {}
        for device_id, device in registered_devices.items():
            ip = device.get('ip', 'unknown')
            geo = get_geoip(ip)
            location = f"{geo.get('city', '')}, {geo.get('country', '')}".strip(', ')
            if not location:
                location = 'Unknown'
            
            key = device.get('device', 'Unknown Device')
            if key not in unique_devices:
                unique_devices[key] = {
                    "deviceId": device_id,
                    "ip": ip,
                    "deviceName": device.get('device', 'Unknown Device'),
                    "deviceModel": device.get('model', 'Unknown'),
                    "manufacturer": device.get('manufacturer', 'Unknown'),
                    "platform": device.get('platform', 'Unknown'),
                    "androidVersion": device.get('androidVersion', 'Unknown'),
                    "macAddress": device.get('macAddress', 'Not Available'),
                    "location": location,
                    "registeredAt": format_timestamp_to_ist_ddmmyy(device.get('registered_at', '')),
                    "lastSeen": format_timestamp_to_ist_ddmmyy(device.get('last_seen', '')),
                    "isActive": device.get('is_active', False),
                }
        return list(unique_devices.values())

    def build_status_payload(self) -> Dict[str, object]:
        memory_info = get_memory_info()
        disk = shutil.disk_usage("/")
        uptime_seconds = get_uptime_seconds()
        battery_info = dict(self.cached_battery_info)
        cloud_status = get_cloud_status()
        docker_containers = get_docker_containers()

        return {
            "type": "server_status",
            "timestamp": iso_now(),
            "hostname": socket.gethostname(),
            "localIp": get_local_ip(),
            "platform": platform.system(),
            "platformRelease": platform.release(),
            "platformVersion": platform.version(),
            "sshConnections": self.ssh_connections,
            "activeSshSessions": get_active_ssh_sessions(),
            "recentSshAttempts": list(recent_ssh_attempts),
            "activeTcpConnections": self.active_tcp_connections,
            "udpConnections": self.udp_connections,
            "uniqueSourceIps": self.unique_source_ips,
            "architecture": platform.machine(),
            "pythonVersion": platform.python_version(),
            "cpuModel": platform.processor() or "Unknown",
            "cpuCores": psutil.cpu_count(logical=True) if psutil is not None else (os.cpu_count() or 1),
            "cpuUsagePercent": get_cpu_usage_percent(),
            "memoryTotalMb": memory_info["memoryTotalMb"],
            "memoryUsedMb": memory_info["memoryUsedMb"],
            "memoryUsagePercent": memory_info["memoryUsagePercent"],
            "diskTotalGb": round(disk.total / (1024**3), 1),
            "diskUsedGb": round(disk.used / (1024**3), 1),
            "diskUsagePercent": round((disk.used / disk.total) * 100, 1) if disk.total else 0.0,
            "uptimeSeconds": uptime_seconds,
            "uptime": format_uptime(uptime_seconds),
            "connectedClients": len(self.active_clients),
            "activeClients": self.get_active_clients_info(),
            "registeredDevices": self.get_registered_devices_info(),
            "rawPacketsSeen": self.raw_packets_seen,
            "packetsCaptured": self.packets_captured,
            "tcpPackets": self.tcp_packets,
            "udpPackets": self.udp_packets,
            "otherPackets": self.other_packets,
            "lastPacketAt": self.last_packet_at,
            "lastPacketSummary": self.last_packet_summary,
            "packetCallbackErrors": self.packet_callback_errors,
            "lastPacketError": self.last_packet_error,
            "packetProcessingQueueDepth": self.packet_processing_queue.qsize(),
            "packetProcessingDrops": self.packet_processing_drops,
            "logsProcessed": self.logs_processed,
            "cloudStatus": cloud_status,
            "dockerContainers": docker_containers,
            **battery_info,
        }

    async def send_json(self, websocket: Any, payload: Dict[str, object]) -> None:
        try:
            await websocket.send(json.dumps(payload))
        except Exception:
            # Remove from active_clients if send fails
            self.active_clients = [c for c in self.active_clients if c['websocket'] != websocket]

    async def broadcast_json(self, payload: Dict[str, object]) -> None:
        if not self.active_clients:
            return

        message = json.dumps(payload)
        targets = [c['websocket'] for c in self.active_clients]
        results = await asyncio.gather(
            *(client.send(message) for client in targets),
            return_exceptions=True,
        )

        for client_info, result in zip(self.active_clients[:], results):
            if isinstance(result, Exception):
                if client_info in self.active_clients:
                    self.active_clients.remove(client_info)

    @staticmethod
    def describe_client(websocket: Any) -> str:
        remote = getattr(websocket, "remote_address", None)
        if isinstance(remote, tuple):
            return f"{remote[0]}:{remote[1]}"
        return str(remote)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Broadcast live packets, logs, and server status over WebSocket.",
    )
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument(
        "--http-port",
        type=int,
        default=5000,
        help="HTTP status/health port for reverse proxies and browser checks (0 disables it).",
    )
    parser.add_argument(
        "--port-retries",
        type=int,
        default=0,
        help="If the requested port is busy, try this many higher ports before failing.",
    )
    parser.add_argument("--iface", default=None, help="Optional capture interface.")
    parser.add_argument(
        "--status-interval",
        type=float,
        default=5.0,
        help="Seconds between status broadcasts.",
    )
    parser.add_argument(
        "--filter",
        dest="bpf_filter",
        default=None,
        help="Optional BPF filter for packet capture.",
    )
    parser.add_argument(
        "--enable-logs",
        action="store_true",
        help="Enable Ubuntu system log watching.",
    )
    parser.add_argument(
        "--enable-packet-sniffing",
        action="store_true",
        default=True,
        help="Enable live packet sniffing (default: True).",
    )
    parser.add_argument(
        "--no-packet-sniffing",
        action="store_true",
        default=False,
        help="Disable packet sniffing.",
    )
    parser.add_argument(
        "--battery-interval",
        type=float,
        default=30.0,
        help="Seconds between battery level checks (default: 30.0).",
    )
    parser.add_argument(
        "--log-paths",
        nargs="*",
        default=None,
        help="Custom log file paths to watch (space-separated).",
    )
    parser.add_argument(
        "--app-token",
        default=os.getenv("PACKET_ANALYZER_APP_TOKEN", DEFAULT_APP_ACCESS_TOKEN),
        help=(
            "Shared token required for /status and WebSocket access. "
            "Can also be set with PACKET_ANALYZER_APP_TOKEN."
        ),
    )
    parser.add_argument(
        "--telegram-bot-token",
        default=TELEGRAM_BOT_TOKEN,
        help=(
            "Telegram bot token for attack alerts. "
            "Can also be set with PACKET_ANALYZER_TELEGRAM_BOT_TOKEN."
        ),
    )
    parser.add_argument(
        "--telegram-chat-id",
        default=TELEGRAM_CHAT_ID,
        help=(
            "Telegram chat id for attack alerts. "
            "Can also be set with PACKET_ANALYZER_TELEGRAM_CHAT_ID."
        ),
    )
    parser.add_argument(
        "--telegram-pin",
        default=TELEGRAM_ADMIN_PIN,
        help=(
            "PIN required for Telegram control commands. "
            "Can also be set with PACKET_ANALYZER_TELEGRAM_PIN."
        ),
    )
    parser.add_argument(
        "--test-telegram-alert",
        action="store_true",
        help="Send a Telegram test alert and exit.",
    )
    return parser.parse_args()


async def async_main() -> None:
    global TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID, TELEGRAM_ADMIN_PIN

    args = parse_args()
    
    # Load state
    load_reputation_from_db()
    
    TELEGRAM_BOT_TOKEN = (args.telegram_bot_token or "").strip()
    TELEGRAM_CHAT_ID = (args.telegram_chat_id or "").strip()
    TELEGRAM_ADMIN_PIN = (args.telegram_pin or "").strip()

    if args.test_telegram_alert:
        if send_alert("Test alert working"):
            print("Telegram test alert sent.")
        else:
            print("Telegram test alert failed or Telegram is not configured.")
        return

    server = PacketServer(
        host=args.host,
        port=args.port,
        http_port=args.http_port,
        port_retries=args.port_retries,
        interface=args.iface,
        status_interval=args.status_interval,
        bpf_filter=args.bpf_filter,
        enable_logs=args.enable_logs,
        log_paths=args.log_paths if args.log_paths else None,
        no_packet_sniffing=not args.enable_packet_sniffing,
        battery_interval=args.battery_interval,
        app_token=args.app_token,
    )
    await server.start()


if __name__ == "__main__":
    try:
        asyncio.run(async_main())
    except OSError as error:
        if is_address_in_use_error(error):
            print(f"❌ {error}")
        else:
            raise
    except KeyboardInterrupt:
        print("Packet server stopped.")


import 'dart:io';

import 'websocket_url_helper.dart';

Future<bool> isSameLocalNetwork(Uri uri) async {
  if (!isPrivateNetworkWebSocketHost(uri) || isLocalOnlyWebSocketHost(uri)) {
    return true;
  }

  final remoteOctets = _ipv4Octets(uri.host);
  if (remoteOctets == null) {
    return true;
  }

  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );

    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        final localOctets = _ipv4Octets(address.address);
        if (localOctets == null) {
          continue;
        }
        if (_isSamePrivateSubnet(localOctets, remoteOctets)) {
          return true;
        }
      }
    }
  } catch (_) {
    return true;
  }

  return false;
}

List<int>? _ipv4Octets(String address) {
  final parts = address.split('.');
  if (parts.length != 4) {
    return null;
  }
  final octets = parts.map(int.tryParse).toList(growable: false);
  if (octets.any((octet) => octet == null)) {
    return null;
  }
  return octets.cast<int>();
}

bool _isSamePrivateSubnet(List<int> local, List<int> remote) {
  if (local[0] == 10 && remote[0] == 10) {
    return local[1] == remote[1] && local[2] == remote[2];
  }
  if (local[0] == 192 && local[1] == 168 &&
      remote[0] == 192 && remote[1] == 168) {
    return local[2] == remote[2];
  }
  if (local[0] == 172 && remote[0] == 172 &&
      local[1] >= 16 && local[1] <= 31 &&
      remote[1] >= 16 && remote[1] <= 31) {
    return local[1] == remote[1] && local[2] == remote[2];
  }
  return false;
}

/// Get the device's local network IP address.
/// Returns the first non-loopback IPv4 address found.
Future<String> getLocalNetworkIp() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );

    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        // Return the first valid address
        if (address.address.isNotEmpty && !address.address.startsWith('127')) {
          return address.address;
        }
      }
    }
  } catch (e) {
    // If we can't get network interfaces, return unknown
    return 'Unknown';
  }

  return 'Unknown';
}

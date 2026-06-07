import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Provides basic connection info using only dart:io — no extra packages needed.
class ConnectionService {
  /// Returns the device's local IPv4 address and a best-guess connection type.
  /// SSID requires platform-specific packages so it is left empty here.
  static Future<({String ssid, String localIp, String type})> getInfo() async {
    if (kIsWeb) return (ssid: '', localIp: '', type: 'Browser');

    try {
      // Use dart:io NetworkInterface to find the first non-loopback IPv4 address.
      final interfaces = await NetworkInterface.list(
        type:            InternetAddressType.IPv4,
        includeLoopback: false,
      );

      String localIp = '';
      String ifName  = '';
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && addr.address.isNotEmpty) {
            localIp = addr.address;
            ifName  = iface.name.toLowerCase();
            break;
          }
        }
        if (localIp.isNotEmpty) break;
      }

      // Heuristic: interface name often hints at the connection type.
      String type = '';
      if (ifName.contains('wlan') || ifName.contains('wifi') || ifName.startsWith('wl')) {
        type = 'Wi-Fi';
      } else if (ifName.contains('rmnet') || ifName.contains('ppp') ||
                 ifName.contains('ccmni') || ifName.startsWith('mobile')) {
        type = 'Mobile';
      } else if (ifName.contains('eth') || ifName.contains('en')) {
        type = 'Ethernet';
      }

      return (ssid: '', localIp: localIp, type: type);
    } catch (_) {
      return (ssid: '', localIp: '', type: '');
    }
  }
}
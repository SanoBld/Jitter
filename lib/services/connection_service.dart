import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectionInfo {
  final String type, ssid, localIp;
  const ConnectionInfo({required this.type, required this.ssid, required this.localIp});
}

class ConnectionService {
  static Future<ConnectionInfo> getInfo() async {
    try {
      final results = await Connectivity().checkConnectivity();
      final result  = results.isNotEmpty ? results.first : ConnectivityResult.none;
      final type = result == ConnectivityResult.wifi
          ? 'Wi-Fi'
          : result == ConnectivityResult.mobile
              ? 'Mobile'
              : result == ConnectivityResult.ethernet
                  ? 'Ethernet'
                  : '';
      String localIp = '';
      try {
        final interfaces = await NetworkInterface.list();
        for (final iface in interfaces) {
          for (final addr in iface.addresses) {
            if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
              localIp = addr.address;
              break;
            }
          }
          if (localIp.isNotEmpty) break;
        }
      } catch (_) {}
      return ConnectionInfo(type: type, ssid: '', localIp: localIp);
    } catch (_) {
      return const ConnectionInfo(type: '', ssid: '', localIp: '');
    }
  }
}
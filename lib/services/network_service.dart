import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class NetworkService {
  static const String _ipPrefKey = 'esp_ip_address';
  static const int _udpPort = 4210;

  static Future<String?> findEspDevice() async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      List<int> data = "FIND_ESP".codeUnits;
      socket.send(data, InternetAddress('255.255.255.255'), _udpPort);

      Completer<String?> completer = Completer();

      StreamSubscription? subscription;
      subscription = socket.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          Datagram? dg = socket!.receive();
          if (dg != null) {
            String message = String.fromCharCodes(dg.data).trim();
            if (message.split('.').length == 4) {
              if (!completer.isCompleted) {
                completer.complete(message);
              }
            }
          }
        }
      });

      return await completer.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          return null;
        },
      ).whenComplete(() {
        subscription?.cancel();
        socket?.close();
      });

    } catch (e) {
      socket?.close();
      return null;
    }
  }

  static Future<void> sendSleepSignal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? espIp = prefs.getString(_ipPrefKey);

      if (espIp == null || espIp.isEmpty) {
        return;
      }

      final url = Uri.parse('http://$espIp/sleep');

      await http.get(url).timeout(const Duration(seconds: 2));
    } catch (e) {}
  }

  static Future<void> saveIpAddress(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ipPrefKey, ip);
  }

  static Future<String> getIpAddress() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_ipPrefKey) ?? "";
  }
}
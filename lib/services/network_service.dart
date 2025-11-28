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

      print("UDP Scanning started...");

      List<int> data = "FIND_ESP".codeUnits;

      // ========================================================
      // [수정된 부분] 신호를 3방향으로 쏩니다 (확률 극대화)
      // ========================================================

      // 1. 전체 방송 (혹시 모르니 유지)
      try {
        socket.send(data, InternetAddress('255.255.255.255'), _udpPort);
      } catch (e) {}

      // 2. 일반적인 안드로이드 핫스팟 대역
      try {
        socket.send(data, InternetAddress('192.168.43.255'), _udpPort);
      } catch (e) {}

      // 3. [중요] 사용자님의 현재 핫스팟 대역 (172.29.158.xxx)
      // 끝자리를 255로 하면 그 동네 전체에 방송합니다.
      try {
        socket.send(data, InternetAddress('172.29.158.255'), _udpPort);
      } catch (e) {
        print("Specific broadcast failed: $e");
      }
      // ========================================================

      Completer<String?> completer = Completer();

      StreamSubscription? subscription;
      subscription = socket.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          Datagram? dg = socket!.receive();
          if (dg != null) {
            String message = String.fromCharCodes(dg.data).trim();
            print("Received response: $message"); // 로그 확인용

            // IP 주소 형식인지 확인 (점 3개)
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
          print("UDP Scan Timeout");
          return null;
        },
      ).whenComplete(() {
        subscription?.cancel();
        socket?.close();
      });

    } catch (e) {
      print("UDP Error: $e");
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
      print("Sending sleep signal to $url"); // 로그 추가

      await http.get(url).timeout(const Duration(seconds: 2));
      print("Signal sent!");
    } catch (e) {
      print("Send Error: $e");
    }
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
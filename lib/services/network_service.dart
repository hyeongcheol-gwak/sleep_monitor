import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class NetworkService {
  static const String _ipPrefKey = 'esp_ip_address';

  static Future<void> sendSleepSignal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? espIp = prefs.getString(_ipPrefKey);

      if (espIp == null || espIp.isEmpty) {
        print("네트워크 오류: ESP IP 주소가 설정되지 않았습니다.");
        return;
      }

      final url = Uri.parse('http://$espIp/sleep');

      print("Sending signal to $url");
      await http.get(url).timeout(const Duration(seconds: 2));
      print("Signal sent successfully");

    } catch (e) {
      print("네트워크 오류 (sendSleepSignal): $e");
    }
  }

  static Future<void> saveIpAddress(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ipPrefKey, ip);
    print("IP 주소 저장 완료: $ip");
  }

  static Future<String> getIpAddress() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_ipPrefKey) ?? "";
  }
}
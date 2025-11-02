import 'package:http/http.dart' as http;
// 휴대폰 저장소에서 IP를 읽어오기 위한 import
import 'package:shared_preferences/shared_preferences.dart';

class NetworkService {
  // IP를 저장할 때 사용할 고유 키
  static const String _ipPrefKey = 'esp_ip_address';

  // ESP에 신호를 보내는 함수
  static Future<void> sendSleepSignal() async {
    try {
      // 신호를 보내기 직전에, 휴대폰에 저장된 IP 주소를 불러옵니다.
      final prefs = await SharedPreferences.getInstance();
      final String? espIp = prefs.getString(_ipPrefKey);

      // 저장된 IP가 없으면(아직 설정 안 함) 경고만 하고 함수 종료
      if (espIp == null || espIp.isEmpty) {
        print("네트워크 오류: ESP IP 주소가 설정되지 않았습니다.");
        return;
      }

      // 불러온 espIp를 사용해 HTTP 요청
      final url = Uri.parse('http://$espIp/sleep');

      print("Sending signal to $url");
      await http.get(url).timeout(const Duration(seconds: 2));
      print("Signal sent successfully.");

    } catch (e) {
      // (기존 오류 처리)
      print("네트워크 오류 (sendSleepSignal): $e");
    }
  }

  // main.dart의 설정 화면에서 호출할 IP 저장 함수
  static Future<void> saveIpAddress(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ipPrefKey, ip);
    print("IP 주소 저장 완료: $ip");
  }

  // 설정 화면에서 현재 저장된 IP를 불러올 함수
  static Future<String> getIpAddress() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_ipPrefKey) ?? ""; // 저장된 값이 없으면 빈칸 반환
  }
}
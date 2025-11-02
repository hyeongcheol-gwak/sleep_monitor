// test/widget_test.dart

import 'package:camera/camera.dart'; // 1. 카메라 패키지 import 추가
import 'package:flutter_test/flutter_test.dart';

import 'package:sleep_monitor/main.dart';

// 2. 테스트용 가짜(mock) 카메라 객체 생성
const CameraDescription mockCamera = CameraDescription(
  name: 'mock',
  lensDirection: CameraLensDirection.front,
  sensorOrientation: 90,
);

void main() {
  testWidgets('App starts in AWAKE state', (WidgetTester tester) async {
    // 3. MyApp을 빌드할 때 'camera' 파라미터를 전달
    await tester.pumpWidget(const MyApp(camera: mockCamera));

    // 4. 앱이 로딩 인디케이터 이후에 AWAKE 상태로 시작하는지 확인
    // (실제로는 카메라 초기화가 필요하므로 pumpAndSettle을 사용)
    await tester.pumpAndSettle();

    // 5. 'AWAKE'라는 텍스트가 있는지 확인 (카운터 로직 삭제)
    expect(find.text('AWAKE'), findsOneWidget);
    expect(find.text('SLEEPING'), findsNothing);
  });
}
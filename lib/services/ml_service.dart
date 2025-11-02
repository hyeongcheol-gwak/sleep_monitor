import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
// import 'dart:developer' as dev; // print()만 사용하므로 삭제
import 'package:audioplayers/audioplayers.dart';

class MLService {
  // ML Kit의 얼굴 감지기. 앱이 살아있는 동안 계속 쓸 거라, 여기에 만들어 둡니다.
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      // 'classification'을 켜야 눈 뜸/감음 확률(probability)을 받을 수 있습니다.
      enableClassification: true,

      // 'fast' (빠름) 대신 'accurate' (정확함) 모드를 사용합니다.
      // 수면 감지는 약간 느려도 정확도가 훨씬 중요합니다.
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  // UI(main.dart) 쪽에 "나 잠들었어!"/"나 깼어!" 신호를 보내는 파이프라인
  final StreamController<bool> _sleepStateController = StreamController<bool>.broadcast();
  Stream<bool> get sleepStateStream => _sleepStateController.stream;

  // '눈 감음', '수면' 알림음을 재생할 플레이어
  final AudioPlayer _audioPlayer = AudioPlayer();

  // --- 상태 관리 변수들 ---
  Timer? _sleepTimer; // '수면' 상태로 넘어가는 5초(예시)를 재는 타이머
  bool _isSleeping = false; // 현재 '수면' 상태인가? (UI 표시 및 ESP 전송용)
  bool _isLoopingSoundPlaying = false; // 현재 '눈 감음' 반복음이 재생 중인가?

  // --- 튜닝 포인트 ---
  // 1. '수면'으로 판단할 '눈 감은' 지속 시간 (기본값: 5초)
  static const Duration _sleepThreshold = Duration(seconds: 5);
  // 2. 눈 뜸/감음을 판단하는 민감도 (0.0 ~ 1.0, 낮을수록 감았다고 판단)
  static const double _eyeOpenThreshold = 0.2;
  // --------------------

  // 카메라에서 받은 이미지를 AI로 분석하는 메인 함수
  Future<void> processCameraImage(CameraImage cameraImage, CameraDescription camera) async {
    // 1. 카메라 이미지를 ML Kit이 알아먹는 'InputImage' 포맷으로 변환
    final InputImage? inputImage = _createInputImage(cameraImage, camera);
    if (inputImage == null) {
      print("이미지 변환 실패. 포맷을 지원하지 않습니다.");
      return;
    }

    // 2. ML Kit으로 이미지에서 얼굴 목록 감지 (await!)
    final List<Face> faces = await _faceDetector.processImage(inputImage);

    // 3. 감지된 얼굴 목록을 가지고 수면 로직 실행
    _detectSleep(faces);
  }

  // 얼굴 목록을 받아 수면/알림 로직을 처리하는 함수
  void _detectSleep(List<Face> faces) {
    // --- 1. 얼굴이 감지되지 않았을 때 ---
    if (faces.isEmpty) {
      _resetSleepTimer("No face detected"); // 모든 상태를 '깨어있음'으로 리셋
      return;
    }

    // (단순화를 위해 첫 번째 감지된 얼굴만 사용합니다)
    final Face face = faces.first;
    final double? leftEyeProb = face.leftEyeOpenProbability;
    final double? rightEyeProb = face.rightEyeOpenProbability;

    // --- 2. 얼굴은 감지됐으나, 눈 확률 값을 못 얻었을 때 (예: 얼굴이 너무 기울어짐) ---
    if (leftEyeProb == null || rightEyeProb == null) {
      _resetSleepTimer("Eye probability not available"); // '깨어있음'으로 리셋
      return;
    }

    // --- 3. 눈 확률 값이 정상적으로 감지되었을 때 ---
    if (leftEyeProb < _eyeOpenThreshold && rightEyeProb < _eyeOpenThreshold) {
      // --- '눈 감음' 상태로 판단 ---

      // '수면' 상태가 아니고, '반복음'도 아직 안 울렸다면?
      if (!_isSleeping && !_isLoopingSoundPlaying) {
        _isLoopingSoundPlaying = true; // "반복음 재생!" 플래그 올리기
        try {
          print("--- EYES CLOSED! 'i_close_my_eyes.mp3' 반복 재생 시작 ---");
          _audioPlayer.setReleaseMode(ReleaseMode.loop);
          _audioPlayer.play(AssetSource('audio/i_close_my_eyes.mp3'));
        } catch (e) {
          print("'i_close_my_eyes.mp3' 재생 실패: $e ");
        }
      }

      // '수면' 상태가 아니라면 (아직 5초 타이머가 안 돌았다면)
      if (!_isSleeping) {
        _startSleepTimer(); // '수면' 카운트다운 타이머 시작
      }

    } else {
      // --- '눈 뜸' 상태로 판단 ---
      _resetSleepTimer("Eyes are open"); // 모든 상태를 '깨어있음'으로 리셋
    }
  }

  // '수면' 카운트다운 타이머 (눈 감은 직후 호출됨)
  void _startSleepTimer() {
    // 이미 타이머가 돌고 있다면 (즉, 이미 눈 감고 5초 세는 중) 또 실행하지 않음
    if (_sleepTimer != null && _sleepTimer!.isActive) return;

    // '수면'까지 남은 시간(_sleepThreshold, 예: 3초) 타이머 시작
    _sleepTimer = Timer(_sleepThreshold, () {

      // 3초가 지났는데, 아직 '수면' 상태가 아니라면 (타이머가 중간에 취소 안 됐다면)
      if (!_isSleeping) {
        print("--- SLEEP DETECTED! '수면' 상태로 전환 ---");

        // 1. '수면' 상태로 전환
        _isSleeping = true;
        // 2. '반복음' 플래그 강제 OFF (눈 떴다 감아도 '반복음'이 다시 켜지지 않게)
        _isLoopingSoundPlaying = false;

        try {
          // 3. (중지) 시끄럽던 '눈 감음' 반복음 즉시 정지
          _audioPlayer.stop();
          print("--- 'i_close_my_eyes.mp3' 반복 재생 정지 ---");

          // 4. (한번 재생) '수면' 알림음(i_fall_asleep.mp3)을 한 번만 재생
          _audioPlayer.setReleaseMode(ReleaseMode.stop);
          _audioPlayer.play(AssetSource('audio/i_fall_asleep.mp3'));
          print("--- 'i_fall_asleep.mp3' 1회 재생 ---");

        } catch (e) {
          print("'i_fall_asleep.mp3' 재생 실패: $e ");
        }

        // UI(main.dart)에 "나 잠들었어!" 신호 전송 (-> ESP에도 신호가 감)
        _sleepStateController.add(true);
      }
    });
  }

  // '눈 뜸' 또는 '얼굴 사라짐' 등, '깨어있음' 상태가 될 때 호출되는 리셋 함수
  void _resetSleepTimer(String reason) {
    // 1. '수면' 카운트다운 타이머가 돌고 있었다면 (즉, 3초가 되기 전에 눈을 떴다면)
    if (_sleepTimer != null && _sleepTimer!.isActive) {
      _sleepTimer!.cancel(); // 타이머 취소
    }

    // 2. '반복음'이 울리고 있었거나, 혹은 이미 '수면' 상태였다면 (즉, 소리가 뭐라도 났었다면)
    if (_isLoopingSoundPlaying || _isSleeping) {
      print("--- EYES OPEN! ($reason) 모든 소리 정지 및 상태 리셋 ---");
      _audioPlayer.stop(); // 모든 오디오(반복이든, 한방이든)를 즉시 정지
    }

    // 3. 모든 상태 플래그를 '깨어있음'(false)으로 되돌립니다.
    if (_isSleeping) {
      // '수면' 상태였다면, UI에도 "나 깼어!" 신호를 보냅니다.
      _sleepStateController.add(false);
    }
    _isSleeping = false;
    _isLoopingSoundPlaying = false;
  }

  // 서비스가 종료될 때(예: 앱이 꺼질 때) 호출
  void dispose() {
    // 모든 컨트롤러와 타이머, 플레이어를 깔끔하게 종료시켜서 메모리 누수를 막습니다.
    _faceDetector.close();
    _sleepStateController.close();
    _sleepTimer?.cancel();
    _audioPlayer.dispose(); // 메모리 누수 버그 수정
  }

  // --- 카메라 이미지 변환 헬퍼 (CameraImage -> InputImage) ---
  InputImage? _createInputImage(CameraImage image, CameraDescription camera) {
    final InputImageRotation rotation =
        InputImageRotationValue.fromRawValue(camera.sensorOrientation) ??
            InputImageRotation.rotation0deg;

    // 1. 카메라 이미지 포맷 그룹 확인
    if (image.format.group == ImageFormatGroup.yuv420) {
      // 2. YUV (안드로이드) 포맷 처리
      final format = InputImageFormat.nv21; // 안드로이드 표준 YUV

      final bytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        bytes.putUint8List(plane.bytes);
      }
      final allBytes = bytes.done().buffer.asUint8List();

      final InputImageMetadata metadata = InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes[0].bytesPerRow,
      );

      return InputImage.fromBytes(
        bytes: allBytes,
        metadata: metadata,
      );
    } else if (image.format.group == ImageFormatGroup.bgra8888) {
      // 3. BGRA (iOS) 포맷 처리
      final format = InputImageFormat.bgra8888;
      final allBytes = image.planes[0].bytes;

      final InputImageMetadata metadata = InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes[0].bytesPerRow,
      );

      return InputImage.fromBytes(
        bytes: allBytes,
        metadata: metadata,
      );
    } else {
      // 4. 지원하지 않는 다른 포맷 (YUV/BGRA가 아니면 AI가 처리 못 함)
      print("지원하지 않는 이미지 포맷입니다: ${image.format.group}");
      return null;
    }
  }
}
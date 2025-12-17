import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:audioplayers/audioplayers.dart';

// 머신러닝을 사용하여 얼굴 감지와 졸음 감지 기능을 제공하는 서비스 클래스입니다.
class MLService {
  // 얼굴 감지를 수행하는 FaceDetector 객체입니다. Google ML Kit을 사용하여 얼굴을 감지합니다.
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      // 눈의 열림 상태를 분류하는 기능을 활성화합니다.
      enableClassification: true,
      // 정확도 모드를 사용하여 더 정확한 얼굴 감지를 수행합니다.
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  // 졸음 상태를 스트림으로 전달하는 컨트롤러입니다. 브로드캐스트 모드로 여러 리스너가 구독할 수 있습니다.
  final StreamController<bool> _sleepStateController = StreamController<bool>.broadcast();
  // 졸음 상태 스트림을 외부에서 접근할 수 있도록 하는 게터입니다.
  Stream<bool> get sleepStateStream => _sleepStateController.stream;

  // 경고음 재생을 위한 오디오 플레이어 객체입니다.
  final AudioPlayer _audioPlayer = AudioPlayer();

  // 알람(비프) 시작 지연 타이머 (눈 감은 후 1초).
  Timer? _alarmTimer;
  // ESP 트리거 지연 타이머 (눈 감은 후 2초).
  Timer? _espTimer;
  // 알람이 울리는 상태 플래그.
  bool _isAlarming = false;
  // ESP 트리거가 이미 발행됐는지 여부.
  bool _espTriggered = false;
  // 경고음 사이의 간격을 조절하는 타이머입니다.
  Timer? _beepGapTimer;
  // 오디오 플레이어의 재생 완료 이벤트를 구독하는 스트림 구독 객체입니다.
  StreamSubscription<void>? _beepLoopSubscription;

  // 알람 시작까지 딜레이 (눈 감은 후 1초).
  static const Duration _alarmDelay = Duration(seconds: 1);
  // 알람이 울린 뒤 ESP 동작까지 추가 딜레이 (알람 시작 후 2초).
  static const Duration _espAfterAlarmDelay = Duration(seconds: 2);
  // 눈이 열려있다고 판단하는 임계값입니다. 이 값보다 낮으면 눈이 감겨있다고 판단합니다.
  static const double _eyeOpenThreshold = 0.4;
  // 경고음 사이의 간격 시간입니다. 200ms마다 경고음이 재생됩니다.
  static const Duration _beepGap = Duration(milliseconds: 200);

  // 카메라에서 받은 이미지를 처리하여 얼굴을 감지하고 졸음을 감지하는 함수입니다.
  Future<void> processCameraImage(CameraImage cameraImage, CameraDescription camera) async {
    // 카메라 이미지를 ML Kit에서 처리할 수 있는 InputImage 형식으로 변환합니다.
    final InputImage? inputImage = _createInputImage(cameraImage, camera);
    // 이미지 변환에 실패하면 함수를 종료합니다.
    if (inputImage == null) {
      return;
    }

    // 얼굴 감지기를 사용하여 이미지에서 얼굴을 찾습니다.
    final List<Face> faces = await _faceDetector.processImage(inputImage);

    // 감지된 얼굴 정보를 사용하여 졸음 상태를 감지합니다.
    _detectSleep(faces);
  }

  // 감지된 얼굴 정보를 분석하여 졸음 상태를 판단하는 함수입니다.
  void _detectSleep(List<Face> faces) {
    // 얼굴이 감지되지 않았으면 타이머/상태를 리셋합니다.
    if (faces.isEmpty) {
      _resetSleepTimer("No face detected");
      return;
    }

    // 첫 번째로 감지된 얼굴을 사용합니다.
    final Face face = faces.first;
    // 왼쪽 눈이 열려있을 확률을 가져옵니다. 0.0에서 1.0 사이의 값입니다.
    final double? leftEyeProb = face.leftEyeOpenProbability;
    // 오른쪽 눈이 열려있을 확률을 가져옵니다. 0.0에서 1.0 사이의 값입니다.
    final double? rightEyeProb = face.rightEyeOpenProbability;

    // 눈의 열림 확률 정보가 없으면 졸음 타이머를 리셋합니다.
    if (leftEyeProb == null || rightEyeProb == null) {
      _resetSleepTimer("Eye probability not available");
      return;
    }

    final bool eyesClosed =
        leftEyeProb < _eyeOpenThreshold && rightEyeProb < _eyeOpenThreshold;

    if (eyesClosed) {
      _startSleepTimers();
    } else {
      _resetSleepTimer("Eyes are open");
    }
  }

  // 눈 감음이 감지되었을 때 알람/ESP 타이머를 시작합니다.
  void _startSleepTimers() {
    // 이미 알람이 스케줄되었으면 재시작하지 않음.
    if ((_alarmTimer?.isActive ?? false) || _isAlarming) return;

    // 알람: 1초 후 시작
    _alarmTimer = Timer(_alarmDelay, () {
      _isAlarming = true;
      _startBeepLoop();

      // 알람 시작 후 2초 뒤 ESP 트리거
      _espTimer = Timer(_espAfterAlarmDelay, () {
        if (_espTriggered) return;
        _espTriggered = true;
        _sleepStateController.add(true);
      });
    });
  }

  // 졸음 타이머를 리셋하는 함수입니다. 눈이 다시 열리면 호출됩니다.
  void _resetSleepTimer(String reason) {
    // 실행 중인 타이머가 있으면 취소합니다.
    _alarmTimer?.cancel();
    _espTimer?.cancel();

    // 알람 중이면 중지.
    if (_isAlarming) {
      _stopBeepLoop();
    }

    // ESP 트리거가 이미 발생했으면 해제 알림.
    if (_espTriggered) {
      _sleepStateController.add(false);
    }
    _isAlarming = false;
    _espTriggered = false;
  }

  // 리소스를 해제하는 함수입니다. 서비스가 더 이상 필요하지 않을 때 호출됩니다.
  void dispose() {
    // 얼굴 감지기를 닫습니다.
    _faceDetector.close();
    // 졸음 상태 스트림 컨트롤러를 닫습니다.
    _sleepStateController.close();
    // 실행 중인 졸음 타이머가 있으면 취소합니다.
    _alarmTimer?.cancel();
    _espTimer?.cancel();
    // 경고음 재생을 중지합니다.
    _stopBeepLoop();
    // 오디오 플레이어를 해제합니다.
    _audioPlayer.dispose();
  }

  // 카메라 이미지를 ML Kit에서 처리할 수 있는 InputImage 형식으로 변환하는 함수입니다.
  InputImage? _createInputImage(CameraImage image, CameraDescription camera) {
    // 카메라 센서의 방향에 따라 이미지 회전 값을 결정합니다. 기본값은 0도입니다.
    final InputImageRotation rotation =
        InputImageRotationValue.fromRawValue(camera.sensorOrientation) ??
            InputImageRotation.rotation0deg;

    // YUV420 형식의 이미지를 처리합니다. 대부분의 모바일 카메라가 이 형식을 사용합니다.
    if (image.format.group == ImageFormatGroup.yuv420) {
      // NV21 형식으로 지정합니다. YUV420의 한 종류입니다.
      final format = InputImageFormat.nv21;

      // 모든 이미지 플레인의 바이트 데이터를 하나의 버퍼에 결합합니다.
      final bytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        bytes.putUint8List(plane.bytes);
      }
      final allBytes = bytes.done().buffer.asUint8List();

      // 이미지의 메타데이터를 생성합니다. 크기, 회전, 형식, 행당 바이트 수를 포함합니다.
      final InputImageMetadata metadata = InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes[0].bytesPerRow,
      );

      // 바이트 데이터와 메타데이터를 사용하여 InputImage를 생성합니다.
      return InputImage.fromBytes(
        bytes: allBytes,
        metadata: metadata,
      );
    // BGRA8888 형식의 이미지를 처리합니다. 일부 플랫폼에서 사용됩니다.
    } else if (image.format.group == ImageFormatGroup.bgra8888) {
      // BGRA8888 형식으로 지정합니다.
      final format = InputImageFormat.bgra8888;
      // 첫 번째 플레인의 바이트 데이터를 사용합니다.
      final allBytes = image.planes[0].bytes;

      // 이미지의 메타데이터를 생성합니다.
      final InputImageMetadata metadata = InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes[0].bytesPerRow,
      );

      // 바이트 데이터와 메타데이터를 사용하여 InputImage를 생성합니다.
      return InputImage.fromBytes(
        bytes: allBytes,
        metadata: metadata,
      );
    // 지원하지 않는 형식이면 null을 반환합니다.
    } else {
      return null;
    }
  }

  // 경고음 재생 루프를 시작하는 함수입니다. 졸음 감지 시 호출됩니다.
  void _startBeepLoop() {
    // 실행 중인 경고음 간격 타이머가 있으면 취소합니다.
    _beepGapTimer?.cancel();
    // 실행 중인 오디오 재생 완료 구독이 있으면 취소합니다.
    _beepLoopSubscription?.cancel();
    // 현재 재생 중인 오디오를 중지합니다.
    _audioPlayer.stop();
    // 오디오 재생 모드를 stop으로 설정합니다. 재생이 완료되면 자동으로 중지됩니다.
    _audioPlayer.setReleaseMode(ReleaseMode.stop);
    // 오디오 재생이 완료되면 다음 경고음을 예약하도록 리스너를 등록합니다.
    _beepLoopSubscription = _audioPlayer.onPlayerComplete.listen((_) {
      _scheduleNextBeep();
    });
    // 첫 번째 경고음을 재생합니다.
    _playBeep();
  }

  // 다음 경고음을 예약하는 함수입니다. 설정된 간격 시간 후에 재생됩니다.
  void _scheduleNextBeep() {
    // 실행 중인 경고음 간격 타이머가 있으면 취소합니다.
    _beepGapTimer?.cancel();
    // 더 이상 졸음 상태가 아니면 함수를 종료합니다.
    if (!_isAlarming) return;
    // 설정된 간격 시간 후에 경고음을 재생하는 타이머를 생성합니다.
    _beepGapTimer = Timer(_beepGap, () {
      // 여전히 졸음 상태이면 경고음을 재생합니다.
      if (_isAlarming) {
        _playBeep();
      }
    });
  }

  // 경고음 파일을 재생하는 함수입니다. assets 폴더에 있는 beep_warning.mp3 파일을 재생합니다.
  Future<void> _playBeep() async {
    try {
      await _audioPlayer.play(AssetSource('audio/beep_warning.mp3'));
    } catch (e) {}
  }

  // 경고음 재생 루프를 중지하는 함수입니다. 눈이 다시 열리면 호출됩니다.
  void _stopBeepLoop() {
    // 실행 중인 경고음 간격 타이머가 있으면 취소합니다.
    _beepGapTimer?.cancel();
    // 실행 중인 오디오 재생 완료 구독이 있으면 취소합니다.
    _beepLoopSubscription?.cancel();
    // 현재 재생 중인 오디오를 중지합니다.
    _audioPlayer.stop();
  }
}

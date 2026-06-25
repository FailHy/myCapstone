import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:provider/provider.dart';

import '../core/services/pose_detector_service.dart';
import '../core/services/logging_service.dart';
import '../core/api/training_service.dart';
import '../features/auth/providers/auth_provider.dart';
import '../core/models/exercise_type.dart';
import 'result_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// WIDGET
// ─────────────────────────────────────────────────────────────────────────────

class TrainingScreen extends StatefulWidget {
  final ExerciseType exerciseType;
  final int targetReps;

  const TrainingScreen({
    super.key,
    required this.exerciseType,
    required this.targetReps,
  });

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  // ── Camera ────────────────────────────────────────────────────────
  CameraController?        _controller;
  List<CameraDescription>? _cameras;
  bool                     _isCameraInitialized = false;

  // ── Pose Detection ────────────────────────────────────────────────
  final PoseDetectorService _poseService = PoseDetectorService();

  // SATU flag — tidak ada frame yang diproses bersamaan
  bool _isProcessingFrame = false;

  // ── Backend / WebSocket ───────────────────────────────────────────
  late TrainingService _trainingService;
  bool                 _isEvaluationStarted = false;

  // ── UI State ──────────────────────────────────────────────────────
  String      _currentFeedback    = 'Tekan Mulai Evaluasi';
  String      _currentState       = '-';
  String      _connectionStatus   = 'Belum terhubung';
  int         _reps               = 0;
  List<Pose>  _detectedPoses      = [];

  // ── FPS Monitor ───────────────────────────────────────────────────
  int      _totalFrames     = 0; // semua frame dari kamera
  int      _processedFrames = 0; // frame yang benar-benar diproses ML Kit
  int      _droppedFrames   = 0; // frame yang di-skip
  DateTime _fpsWindowStart  = DateTime.now();
  double   _currentFps      = 0;
  double   _processedFps    = 0;

  // ── Throttling adaptif ────────────────────────────────────────────
  DateTime?               _lastProcessedTime;
  static const Duration   _targetInterval = Duration(milliseconds: 100); // ~10fps

  // ── Logger ────────────────────────────────────────────────────────
  final TrainingLogger _logger = TrainingLogger();
  DateTime?            _evalStartTime;

  // ─────────────────────────────────────────────────────────────────────
  // LIFECYCLE
  // ─────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _poseService.initialize();
    _initService();
    _initCamera();
  }

  @override
  void dispose() {
    // Urutan dispose penting — stop stream dulu, lalu resources
    _stopEvaluation();
    _controller?.dispose();
    _poseService.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────
  // INIT SERVICE
  // ─────────────────────────────────────────────────────────────────────

  void _initService() {
    _trainingService = TrainingService(
      onEvaluationReceived: (result) {
        _logger.logBackendResponse(result);
        if (!mounted) return;
        setState(() {
          // [FIX B6-01] Backend kirim 'rep_count', bukan 'reps'
          if (result['status'] == 'rep_completed') {
            _reps = result['rep_count'] is int
                ? result['rep_count'] as int
                : (result['rep_count'] as num?)?.toInt() ?? _reps;
          }
          // [FIX B6-02] Tampilkan feedback actionable dari backend
          final fb = result['feedback']?.toString();
          if (fb != null && fb.isNotEmpty) _currentFeedback = fb;

          _currentState     = result['smoothed_prediction']?.toString() ?? '-';
          _connectionStatus = 'Terhubung ✓';
          
          // Auto-stop jika target terpenuhi
          if (_reps >= widget.targetReps && _isEvaluationStarted) {
            _stopEvaluation();
          }
        });
      },
      onError: (error) {
        _logger.logWebSocketError(error); // ← LOG ERROR
        debugPrint('[TrainingScreen] ❌ Service error: $error');
        if (!mounted) return;
        setState(() => _connectionStatus = 'Error: $error');
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // INIT CAMERA
  // ─────────────────────────────────────────────────────────────────────

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        debugPrint('[TrainingScreen] ❌ Tidak ada kamera tersedia');
        return;
      }

      // Prioritaskan kamera depan
      final camera = _cameras!.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras!.first,
      );

      debugPrint(
        '[TrainingScreen] 📷 Kamera: ${camera.name} | '
        'sensorOrientation=${camera.sensorOrientation}',
      );

      _controller = CameraController(
        camera,
        // LOW = mencegah buffer bloat di Infinix/MediaTek
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );

      await _controller!.initialize();
      if (!mounted) return;

      setState(() => _isCameraInitialized = true);
      debugPrint('[TrainingScreen] ✅ Kamera siap');

      // ── LOG kamera setelah berhasil init ──────────────────────────
      final previewSize = _controller!.value.previewSize;
      _logger.logCameraInit(
        width:             previewSize?.width.toInt()  ?? 0,
        height:            previewSize?.height.toInt() ?? 0,
        sensorOrientation: camera.sensorOrientation,
        resolution:        'low',
        formatGroup:       defaultTargetPlatform == TargetPlatform.iOS
            ? 'bgra8888' : 'yuv420',
      );
    } catch (e) {
      debugPrint('[TrainingScreen] ❌ Error init kamera: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // START / STOP
  // ─────────────────────────────────────────────────────────────────────

  Future<void> _startEvaluation() async {
    if (_isEvaluationStarted) return;

    setState(() {
      _currentFeedback  = 'Menghubungkan ke server...';
      _connectionStatus = 'Connecting...';
    });

    // Ambil userId dari AuthProvider
    final userId = context.read<AuthProvider>().userId;
    final effectiveId = userId.isNotEmpty ? userId : 'guest';

    // ── Buka file log ─────────────────────────────────────────────
    await _logger.open();
    _logger.logSessionStart(
      userId: effectiveId,
      exerciseType: widget.exerciseType.backendCode,
    );

    final success = await _trainingService.startSession(
      userId:       effectiveId,
      exerciseType: widget.exerciseType.backendCode,
    );

    if (!success) {
      _logger.logWebSocketError('startSession gagal — server tidak dapat dihubungi');
      await _logger.close();
      if (!mounted) return;
      setState(() {
        _currentFeedback  = 'Gagal terhubung ke server';
        _connectionStatus = 'Offline';
      });
      return;
    }

    // ── Log WebSocket connect ─────────────────────────────────────
    _logger.logWebSocketConnect(
      url:       'ws://10.93.254.195:8000/ws',
      sessionId: 'connected',
    );

    _evalStartTime = DateTime.now();

    if (!mounted) return;
    setState(() {
      _isEvaluationStarted = true;
      _currentFeedback     = 'Deteksi Pose Aktif';
      _connectionStatus    = 'Terhubung ✓';
      _totalFrames     = 0;
      _processedFrames = 0;
      _droppedFrames   = 0;
      _fpsWindowStart  = DateTime.now();
    });

    try {
      if (_controller != null && _controller!.value.isInitialized) {
        await _controller!.startImageStream(_onCameraFrame);
        _logger.logEvalStart(); // ← LOG EVAL START
        debugPrint('[TrainingScreen] 📡 Image stream dimulai');
        debugPrint('[TrainingScreen] 📝 Log: ${_logger.logFilePath}');
      }
    } catch (e) {
      debugPrint('[TrainingScreen] ❌ Gagal start stream: $e');
      setState(() => _currentFeedback = 'Gagal mulai kamera');
    }
  }

  Future<void> _stopEvaluation() async {
    if (!_isEvaluationStarted) return;

    // Stop camera stream terlebih dahulu
    try {
      if (_controller != null && _controller!.value.isStreamingImages) {
        await _controller!.stopImageStream();
      }
    } catch (e) {
      debugPrint('[TrainingScreen] ⚠️ Stop stream error: $e');
    }

    // [FIX B2-01] Akhiri sesi ke backend dan ambil hasil
    final sessionResult = await _trainingService.endSession();

    // Log eval stop
    final duration = _evalStartTime != null
        ? DateTime.now().difference(_evalStartTime!)
        : Duration.zero;
    _logger.logEvalStop(
      duration:        duration,
      totalFrames:     _totalFrames + _processedFrames + _droppedFrames,
      processedFrames: _processedFrames,
      reps:            _reps,
    );
    await _logger.close();

    if (!mounted) return;
    setState(() {
      _isEvaluationStarted = false;
      _currentFeedback     = 'Selesai';
      _connectionStatus    = '';
      _detectedPoses       = [];
    });

    // [FIX B5-03] Navigasi ke ResultScreen dengan data nyata
    if (sessionResult != null && mounted) {
      final backendErrorDist = sessionResult['error_distribution'] as Map<String, dynamic>?;
      final errorDist = backendErrorDist?.map((k, v) => MapEntry(k, v as int)) ?? {};
      
      final result = TrainingResult(
        exerciseType: widget.exerciseType,
        totalReps:    (sessionResult['total_reps']   as num?)?.toInt()    ?? _reps,
        correctReps:  (sessionResult['correct_reps'] as num?)?.toInt()    ?? 0,
        accuracy:     (sessionResult['accuracy']     as num?)?.toDouble() ?? 0.0,
        errorDistribution: errorDist,
      );
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ResultScreen(result: result)),
      );
    }
  }


  // ─────────────────────────────────────────────────────────────────────
  // CAMERA FRAME CALLBACK
  // ─────────────────────────────────────────────────────────────────────

  Future<void> _onCameraFrame(CameraImage image) async {
    if (!_isEvaluationStarted) return;

    _totalFrames++;
    _updateFpsCounter();

    // ── SATU FRAME PADA SATU WAKTU — drop jika masih processing ─────
    if (_isProcessingFrame) {
      _droppedFrames++;
      return;
    }

    // ── Throttling adaptif: target ~10fps ────────────────────────────
    final now = DateTime.now();
    if (_lastProcessedTime != null &&
        now.difference(_lastProcessedTime!) < _targetInterval) {
      _droppedFrames++;
      return;
    }

    _lastProcessedTime  = now;
    _isProcessingFrame  = true;

    try {
      // ── Dapatkan sensorOrientation dari kamera aktif ─────────────
      final camera = _cameras!.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras!.first,
      );

      // ── Proses via PoseDetectorService ───────────────────────────
      final Map<PoseLandmarkType, PoseLandmark>? landmarks =
          await _poseService.processCameraImage(
        image,
        camera.sensorOrientation,
      );

      _processedFrames++;

      // ── Update stats UI ──────────────────────────────────────────
      if (mounted) {
        setState(() {
          _detectedPoses = _poseService.lastPoses; // ← isi untuk PosePainter
          if (landmarks != null && landmarks.isNotEmpty) {
            _currentState = 'Pose Terdeteksi! (${landmarks.length} pts)';
          } else {
            _currentState = 'Tubuh tidak terlihat';
          }
        });
      }

      // ── Ekstrak 4 landmark utama dan kirim ke backend ────────────
      Map<String, Map<String, dynamic>>? extracted;
      if (landmarks != null && landmarks.isNotEmpty) {
        extracted = _extractKeyLandmarks(landmarks);
        if (extracted != null) {
          _trainingService.sendFrameData(extracted);
        }
      }

      // ── Akumulasi ke logger (1 sample per window) ─────────────────
      _logger.accumulateFrame(
        processed:       true,
        dropped:         false,
        infMs:           _poseService.lastProcessingMs,
        sampleLandmarks: extracted,
      );
    } catch (e) {
      debugPrint('[TrainingScreen] ❌ Error proses frame: $e');
    } finally {
      _isProcessingFrame = false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // LANDMARK EXTRACTION + VALIDATION
  // ─────────────────────────────────────────────────────────────────────

  /// Ekstrak 4 landmark utama.
  /// Mengembalikan null jika ada landmark yang tidak valid
  /// (semua koordinat nol atau confidence < 50%).
  Map<String, Map<String, dynamic>>? _extractKeyLandmarks(
    Map<PoseLandmarkType, PoseLandmark> landmarks,
  ) {
    final shoulder = landmarks[PoseLandmarkType.rightShoulder];
    final elbow    = landmarks[PoseLandmarkType.rightElbow];
    final wrist    = landmarks[PoseLandmarkType.rightWrist];
    final hip      = landmarks[PoseLandmarkType.rightHip];

    // Semua 4 landmark wajib ada
    if (shoulder == null || elbow == null || wrist == null || hip == null) {
      debugPrint('[TrainingScreen] ⚠️ Landmark utama tidak lengkap');
      return null;
    }

    final extracted = {
      'shoulder': _toMap(shoulder),
      'elbow':    _toMap(elbow),
      'wrist':    _toMap(wrist),
      'hip':      _toMap(hip),
    };

    // Validasi: tidak semua titik boleh nol
    final allZero = extracted.values.every(
      (p) => p['x'] == 0.0 && p['y'] == 0.0 && p['z'] == 0.0,
    );
    if (allZero) return null;

    // Validasi: confidence minimal 50%
    final hasLowConfidence = extracted.values.any(
      (p) => (p['visibility'] as double) < 0.5,
    );
    if (hasLowConfidence) {
      if (mounted) setState(() => _currentState = 'Akurasi pose rendah...');
      return null;
    }

    return extracted;
  }

  Map<String, dynamic> _toMap(PoseLandmark lm) => {
    'x':          lm.x,
    'y':          lm.y,
    'z':          lm.z,
    'visibility': lm.likelihood,
  };

  // ─────────────────────────────────────────────────────────────────────
  // FPS MONITOR
  // ─────────────────────────────────────────────────────────────────────

  void _updateFpsCounter() {
    final elapsed = DateTime.now().difference(_fpsWindowStart);
    if (elapsed.inMilliseconds >= 1000) {
      final double secs = elapsed.inMilliseconds / 1000.0;
      setState(() {
        _currentFps   = _totalFrames     / secs;
        _processedFps = _processedFrames / secs;
        // Reset window
        _totalFrames     = 0;
        _processedFrames = 0;
        _fpsWindowStart  = DateTime.now();
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          '${widget.exerciseType.displayName.toUpperCase()} ($_reps/${widget.targetReps})',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildCameraView()),
            _buildControlPanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraView() {
    if (!_isCameraInitialized || _controller == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.blueAccent),
            SizedBox(height: 16),
            Text('Membuka Kamera...', style: TextStyle(color: Colors.white)),
          ],
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(_controller!),

        // Pose overlay
        if (_detectedPoses.isNotEmpty)
          CustomPaint(
            painter: PosePainter(
              _detectedPoses,
              _controller!.value.previewSize!,
              InputImageRotation.rotation270deg,
            ),
          ),

        // FPS Monitor overlay (kiri atas)
        Positioned(
          top: 12,
          left: 12,
          child: _FpsOverlay(
            cameraFps:    _currentFps,
            processedFps: _processedFps,
            dropped:      _droppedFrames,
            poseDropped:  _poseService.droppedFrames,
            lastMs:       _poseService.lastProcessingMs,
          ),
        ),

        // Status bar (bawah)
        Positioned(
          bottom: 16,
          left: 0,
          right: 0,
          child: Center(
            child: _StatusBadge(
              feedback:   _currentFeedback,
              state:      _currentState,
              connection: _connectionStatus,
              reps:       _reps,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildControlPanel() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () async {
              await _stopEvaluation();
              if (mounted && Navigator.canPop(context)) Navigator.pop(context);
            },
            icon:  const Icon(Icons.stop_circle_outlined),
            label: const Text('Selesai', style: TextStyle(fontSize: 16)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _isEvaluationStarted
                  ? Colors.grey.shade400
                  : Colors.green.shade600,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: _isCameraInitialized && !_isEvaluationStarted
                ? _startEvaluation
                : null,
            icon:  const Icon(Icons.play_circle_fill),
            label: const Text('Mulai', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPER WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _FpsOverlay extends StatelessWidget {
  final double cameraFps;
  final double processedFps;
  final int    dropped;
  final int    poseDropped;
  final double lastMs;

  const _FpsOverlay({
    required this.cameraFps,
    required this.processedFps,
    required this.dropped,
    required this.poseDropped,
    required this.lastMs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(
          color: Colors.greenAccent,
          fontSize: 11,
          fontFamily: 'monospace',
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('CAM  ${cameraFps.toStringAsFixed(1)} fps'),
            Text('POSE ${processedFps.toStringAsFixed(1)} fps'),
            Text('DROP ${dropped + poseDropped} frames'),
            Text('INF  ${lastMs.toStringAsFixed(0)} ms'),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String feedback;
  final String state;
  final String connection;
  final int    reps;

  const _StatusBadge({
    required this.feedback,
    required this.state,
    required this.connection,
    required this.reps,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.indigo.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            feedback.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          if (state != '-')
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                state,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          if (reps > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Reps: $reps',
                style: const TextStyle(
                  color: Colors.amberAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (connection.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                connection,
                style: TextStyle(
                  color: connection.contains('✓')
                      ? Colors.greenAccent
                      : Colors.orangeAccent,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// POSE PAINTER
// ─────────────────────────────────────────────────────────────────────────────

class PosePainter extends CustomPainter {
  final List<Pose>         poses;
  final Size               imageSize;
  final InputImageRotation rotation;

  const PosePainter(this.poses, this.imageSize, this.rotation);

  @override
  void paint(Canvas canvas, Size size) {
    final jointPaint = Paint()
      ..style       = PaintingStyle.fill
      ..color       = Colors.greenAccent
      ..strokeWidth = 4.0;

    final bonePaint = Paint()
      ..style       = PaintingStyle.stroke
      ..color       = Colors.greenAccent.withValues(alpha: 0.6)
      ..strokeWidth = 2.0;

    // Skala — gambar landscape, layar portrait → sumbu dibalik
    final double scaleX = size.width  / imageSize.height;
    final double scaleY = size.height / imageSize.width;

    for (final pose in poses) {
      // Gambar titik landmark
      pose.landmarks.forEach((_, lm) {
        if (lm.likelihood < 0.3) return; // skip titik tidak yakin
        final offset = _toOffset(lm, size, scaleX, scaleY);
        canvas.drawCircle(offset, 5, jointPaint);
      });

      // Gambar tulang (koneksi antar landmark)
      _drawBones(canvas, pose, size, scaleX, scaleY, bonePaint);
    }
  }

  Offset _toOffset(
      PoseLandmark lm, Size size, double sx, double sy) {
    return Offset(
      size.width - (lm.y * sx), // rotasi 270° untuk kamera depan
      lm.x * sy,
    );
  }

  void _drawBones(Canvas canvas, Pose pose, Size size,
      double sx, double sy, Paint paint) {
    final connections = [
      [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
      [PoseLandmarkType.rightElbow,    PoseLandmarkType.rightWrist],
      [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],
      [PoseLandmarkType.leftShoulder,  PoseLandmarkType.leftElbow],
      [PoseLandmarkType.leftElbow,     PoseLandmarkType.leftWrist],
      [PoseLandmarkType.leftShoulder,  PoseLandmarkType.leftHip],
      [PoseLandmarkType.rightShoulder, PoseLandmarkType.leftShoulder],
      [PoseLandmarkType.rightHip,      PoseLandmarkType.leftHip],
    ];

    for (final pair in connections) {
      final a = pose.landmarks[pair[0]];
      final b = pose.landmarks[pair[1]];
      if (a == null || b == null) continue;
      if (a.likelihood < 0.3 || b.likelihood < 0.3) continue;
      canvas.drawLine(
        _toOffset(a, size, sx, sy),
        _toOffset(b, size, sx, sy),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant PosePainter old) =>
      old.poses != poses || old.imageSize != imageSize;
}

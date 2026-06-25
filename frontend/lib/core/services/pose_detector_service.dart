import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../utils/image_converter.dart';

/// Service tunggal untuk pose detection berbasis ML Kit.
///
/// Lifecycle yang benar:
///   1. Buat instance sekali di StatefulWidget
///   2. Panggil [initialize]
///   3. Gunakan [processCameraImage] di setiap frame
///   4. Panggil [dispose] di widget.dispose()
class PoseDetectorService {
  PoseDetector? _poseDetector;

  // Flag atomic agar tidak ada frame yang diproses secara bersamaan
  bool _isProcessing = false;

  // Statistik performa — bisa ditampilkan di UI debug
  int    _processedFrames = 0;
  int    _droppedFrames   = 0;
  double _lastProcessingMs = 0;

  int    get processedFrames  => _processedFrames;
  int    get droppedFrames    => _droppedFrames;
  double get lastProcessingMs => _lastProcessingMs;

  // Pose terakhir yang berhasil dideteksi — untuk PosePainter
  List<Pose> _lastPoses = [];
  List<Pose> get lastPoses => _lastPoses;

  bool get isInitialized => _poseDetector != null;

  // ------------------------------------------------------------------
  // LIFECYCLE
  // ------------------------------------------------------------------

  /// Inisialisasi PoseDetector. Panggil sekali setelah widget dibuat.
  void initialize() {
    if (_poseDetector != null) {
      debugPrint('[PoseDetector] ⚠️ Sudah diinisialisasi — skip duplicate init');
      return;
    }
    _poseDetector = PoseDetector(
      options: PoseDetectorOptions(
        model: PoseDetectionModel.base,
        mode: PoseDetectionMode.stream,
      ),
    );
    debugPrint('[PoseDetector] ✅ Inisialisasi berhasil (stream mode, base model)');
  }

  /// Tutup PoseDetector dan bebaskan sumber daya native.
  void dispose() {
    _poseDetector?.close();
    _poseDetector = null;
    debugPrint(
      '[PoseDetector] 🔒 Disposed — '
      'processed=$_processedFrames dropped=$_droppedFrames',
    );
  }

  // ------------------------------------------------------------------
  // CORE PROCESSING
  // ------------------------------------------------------------------

  /// Proses satu [CameraImage] dan kembalikan map landmark → koordinat.
  ///
  /// Mengembalikan `null` jika:
  /// • Belum diinisialisasi
  /// • Sedang memproses frame sebelumnya (frame drop)
  /// • Konversi gambar gagal
  /// • Tidak ada pose terdeteksi
  /// • Exception terjadi
  ///
  /// Parameter [sensorOrientation] diambil dari [CameraDescription.sensorOrientation].
  Future<Map<PoseLandmarkType, PoseLandmark>?> processCameraImage(
    CameraImage image,
    int sensorOrientation,
  ) async {
    if (_poseDetector == null) {
      debugPrint('[PoseDetector] ❌ Belum diinisialisasi. Panggil initialize() dulu.');
      return null;
    }

    // Drop frame jika masih memproses — tidak boleh queue
    if (_isProcessing) {
      _droppedFrames++;
      return null;
    }

    _isProcessing = true;
    final stopwatch = Stopwatch()..start();

    try {
      // ── Konversi format ──────────────────────────────────────────────
      final Uint8List? nv21Bytes = ImageConverter.yuv420ToNV21(image);
      if (nv21Bytes == null) {
        debugPrint('[PoseDetector] ⚠️ Konversi NV21 gagal — frame di-skip');
        return null;
      }

      // ── Buat InputImage ──────────────────────────────────────────────
      final InputImageRotation rotation =
          InputImageRotationValue.fromRawValue(sensorOrientation) ??
          InputImageRotation.rotation270deg;

      final InputImageMetadata metadata = InputImageMetadata(
        size:        Size(image.width.toDouble(), image.height.toDouble()),
        rotation:    rotation,
        format:      InputImageFormat.nv21,
        bytesPerRow: image.planes[0].bytesPerRow,
      );

      final InputImage inputImage = InputImage.fromBytes(
        bytes:    nv21Bytes,
        metadata: metadata,
      );

      // ── Inferensi ML Kit ─────────────────────────────────────────────
      final List<Pose> poses = await _poseDetector!.processImage(inputImage);

      stopwatch.stop();
      _lastProcessingMs = stopwatch.elapsedMilliseconds.toDouble();
      _processedFrames++;

      if (poses.isEmpty) {
        debugPrint(
          '[PoseDetector] 👤 Tidak ada pose — ${_lastProcessingMs.toStringAsFixed(0)}ms',
        );
        return null;
      }

      final Map<PoseLandmarkType, PoseLandmark> landmarks =
          poses.first.landmarks;

      _lastPoses = poses; // simpan untuk PosePainter

      if (landmarks.isEmpty) {
        debugPrint('[PoseDetector] ⚠️ Pose ditemukan tapi landmarks kosong');
        return null;
      }

      debugPrint(
        '[PoseDetector] ✅ ${landmarks.length} landmarks | '
        '${_lastProcessingMs.toStringAsFixed(0)}ms | '
        'dropped=$_droppedFrames',
      );

      return landmarks;
    } catch (e, st) {
      // Tangkap exception tapi JANGAN hentikan stream kamera
      debugPrint('[PoseDetector] ❌ Exception: $e\n$st');
      return null;
    } finally {
      // Wajib reset — bahkan saat exception
      _isProcessing = false;
    }
  }
}
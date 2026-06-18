import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

class TrainingScreen extends StatefulWidget {
  const TrainingScreen({super.key});

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  // PERBAIKAN: Logika untuk membuka kamera depan
  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      
      if (_cameras != null && _cameras!.isNotEmpty) {
        // Cari kamera depan, jika tidak ada gunakan kamera apa pun yang tersedia
        final frontCamera = _cameras!.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.front,
          orElse: () => _cameras!.first,
        );

        _controller = CameraController(
          frontCamera,
          ResolutionPreset.medium, // Menghemat resource CPU/RAM untuk pemrosesan ML
          enableAudio: false,      // Matikan audio karena AI hanya butuh visual
        );

        await _controller!.initialize();
        
        if (!mounted) return;
        
        setState(() {
          _isCameraInitialized = true;
        });
      }
    } catch (e) {
      debugPrint("Error inisialisasi kamera: $e");
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Sesi Latihan', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _isCameraInitialized && _controller != null
                  ? Stack(
                      alignment: Alignment.center,
                      children: [
                        // Tampilan feed Kamera
                        SizedBox(
                          width: double.infinity,
                          child: CameraPreview(_controller!),
                        ),
                        // Overlay Teks Bantuan
                        Positioned(
                          bottom: 20,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Posisikan seluruh tubuh di dalam layar',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        )
                      ],
                    )
                  : const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: Colors.blueAccent),
                          SizedBox(height: 16),
                          Text('Membuka Kamera...', style: TextStyle(color: Colors.white)),
                        ],
                      ),
                    ),
            ),
            // Panel Tombol Bawah
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.stop),
                    label: const Text('Selesai'),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _isCameraInitialized ? () {
                      // TODO: Nantinya di sini kita buat koneksi ke WebSocket backend
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('AI Evaluasi akan dimulai!'))
                      );
                    } : null,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Mulai Evaluasi'),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
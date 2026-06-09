import 'package:flutter/material.dart';
import '../theme.dart';

class TrainingScreen extends StatefulWidget {
  const TrainingScreen({super.key});

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  bool isTraining = false;
  int reps = 0;

  // TODO: Integrate WebRTC/Camera preview here.
  // TODO: Connect WebSocket for real-time ML pose estimation parsing.

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. Camera Background Layer
          Container(
            color: Colors.black, // Placeholder for actual Camera widget
            child: const Center(
              child: Text(
                'Camera Preview Active',
                style: TextStyle(color: Colors.white24),
              ),
            ),
          ),

          // 2. Alignment Guide Overlay
          Center(
            child: Container(
              width: 250,
              height: 450,
              decoration: BoxDecoration(
                border: Border.all(
                  color: AppTheme.accentLime.withOpacity(0.5),
                  width: 2,
                  style: BorderStyle.solid,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),

          // 3. UI Layer (Safe Area)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Top Row: Instruction & Rep Counter
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Instruction Pill
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Center your body',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      // Reps Counter
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceDark.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.accentLime),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'REPS',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '$reps',
                              style: const TextStyle(
                                color: AppTheme.accentLime,
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Bottom Controls
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FloatingActionButton.large(
                        heroTag: 'control_btn',
                        backgroundColor:
                            isTraining ? Colors.redAccent : AppTheme.accentLime,
                        onPressed: () {
                          if (isTraining) {
                            // Finish and go to results
                            Navigator.pushReplacementNamed(context, '/result');
                          } else {
                            setState(() => isTraining = true);
                            // TODO: Start ML inference stream
                          }
                        },
                        child: Icon(
                          isTraining ? Icons.stop : Icons.play_arrow,
                          color:
                              isTraining ? Colors.white : AppTheme.primaryNavy,
                          size: 40,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

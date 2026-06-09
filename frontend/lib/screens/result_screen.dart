import 'package:flutter/material.dart';
import '../widgets/custom_widgets.dart';
import '../theme.dart';

class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              const Center(
                child: Text(
                  'Training Result',
                  style: TextStyle(color: Colors.white70, fontSize: 18),
                ),
              ),
              const SizedBox(height: 16),

              // Big Status
              const Center(
                child: Text(
                  'Needs Improvement',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.orangeAccent,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 48),

              // Stats Row
              const Row(
                children: [
                  StatsCard(title: 'Correct Reps', value: '8'),
                  SizedBox(width: 16),
                  StatsCard(title: 'Incorrect', value: '4'),
                ],
              ),
              const SizedBox(height: 32),

              // AI Insights Box
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceDark,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI Insights',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.greenAccent),
                        SizedBox(width: 8),
                        Text(
                          'Good pacing and back posture.',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.orangeAccent,
                        ),
                        SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Keep elbows tucked in during curls.',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Actions
              PrimaryButton(
                text: 'Try Again',
                onPressed:
                    () => Navigator.pushReplacementNamed(context, '/training'),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed:
                    () => Navigator.pop(context), // Pops back to MainNavigation
                child: const Text(
                  'Back to Home',
                  style: TextStyle(color: Colors.white54, fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

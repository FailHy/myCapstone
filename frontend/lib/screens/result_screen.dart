import 'package:flutter/material.dart';
import 'package:frontend/screens/training_setup_screen.dart';
import '../core/models/exercise_type.dart';

class TrainingResult {
  final ExerciseType exerciseType;
  final int totalReps;
  final int correctReps;
  final double accuracy;
  final Map<String, int> errorDistribution;

  const TrainingResult({
    required this.exerciseType,
    required this.totalReps,
    required this.correctReps,
    required this.accuracy,
    required this.errorDistribution,
  });

  int get incorrectReps => totalReps - correctReps;
  String get grade {
    if (accuracy >= 85) return 'Sangat Baik';
    if (accuracy >= 65) return 'Baik';
    if (accuracy >= 45) return 'Cukup';
    return 'Perlu Latihan';
  }

  Color get gradeColor {
    if (accuracy >= 85) return Colors.greenAccent;
    if (accuracy >= 65) return Colors.lightBlueAccent;
    if (accuracy >= 45) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  String get insight {
    if (accuracy >= 85) {
      return 'Gerakan Anda sangat terkontrol. Pertahankan form ini!';
    }
    if (accuracy >= 65) {
      return 'Gerakan sudah bagus. Fokus pada ROM yang lebih penuh.';
    }
    if (accuracy >= 45) {
      return 'Kurangi kecepatan dan pastikan siku tidak keluar.';
    }
    return 'Perhatikan postur dan isolasi otot target. Mulai dari beban ringan.';
  }
}

class ResultScreen extends StatelessWidget {
  final TrainingResult result;
  const ResultScreen({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D1A),
        elevation: 0,
        title: const Text(
          'Training Result',
          style: TextStyle(color: Colors.white70, fontSize: 18),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: result.gradeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(40),
                    border: Border.all(color: result.gradeColor, width: 1.5),
                  ),
                  child: Text(
                    result.grade,
                    style: TextStyle(
                      color: result.gradeColor,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.greenAccent.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'Correct',
                            style: TextStyle(color: Colors.white54),
                          ),
                          Text(
                            '${result.correctReps}',
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.redAccent.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'Incorrect',
                            style: TextStyle(color: Colors.white54),
                          ),
                          Text(
                            '${result.incorrectReps}',
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'Performance Insights',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.check_circle,
                          color: Colors.greenAccent,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            result.insight,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (result.errorDistribution.isNotEmpty) ...[
                      const Divider(color: Colors.white24),
                      ...result.errorDistribution.entries.map((entry) {
                        final errorName = entry.key
                            .split('_')
                            .map(
                              (word) =>
                                  word.isNotEmpty
                                      ? '${word[0].toUpperCase()}${word.substring(1)}'
                                      : '',
                            )
                            .join(' ');
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.warning,
                                color: Colors.orangeAccent,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '$errorName: ${entry.value}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed:
                          () => Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder:
                                  (context) => TrainingSetupScreen(
                                    exerciseType: result.exerciseType,
                                  ),
                            ),
                          ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      child: const Text('Try Again'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          () =>
                              Navigator.of(context).popUntil((r) => r.isFirst),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      child: const Text('Back To Home'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

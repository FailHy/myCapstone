import 'package:flutter/material.dart';
import '../core/models/exercise_type.dart';

/// Model data hasil satu sesi latihan.
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
    if (accuracy >= 85) return 'Gerakan Anda sangat terkontrol. Pertahankan form ini!';
    if (accuracy >= 65) return 'Gerakan sudah bagus. Fokus pada ROM yang lebih penuh.';
    if (accuracy >= 45) return 'Kurangi kecepatan dan pastikan siku tidak keluar.';
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
        title: Text(
          'Hasil Latihan — ${result.exerciseType.displayName.toUpperCase()}',
          style: const TextStyle(color: Colors.white70, fontSize: 16),
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
              const SizedBox(height: 8),

              // Grade badge
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
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
              const SizedBox(height: 32),

              // Accuracy ring
              Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 140,
                      height: 140,
                      child: CircularProgressIndicator(
                        value: result.accuracy / 100,
                        strokeWidth: 12,
                        backgroundColor: Colors.white10,
                        valueColor: AlwaysStoppedAnimation<Color>(result.gradeColor),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${result.accuracy.toStringAsFixed(1)}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Text(
                          'Akurasi',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Stats row
              Row(
                children: [
                  _StatCard(
                    label: 'Total Reps',
                    value: '${result.totalReps}',
                    color: Colors.white,
                    icon: Icons.repeat,
                  ),
                  const SizedBox(width: 12),
                  _StatCard(
                    label: 'Benar',
                    value: '${result.correctReps}',
                    color: Colors.greenAccent,
                    icon: Icons.check_circle_outline,
                  ),
                  const SizedBox(width: 12),
                  _StatCard(
                    label: 'Salah',
                    value: '${result.incorrectReps}',
                    color: Colors.orangeAccent,
                    icon: Icons.warning_amber_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              // Error Distribution
              if (result.errorDistribution.isNotEmpty) ...[
                const Text(
                  'Distribusi Kesalahan:',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: result.errorDistribution.entries.map((entry) {
                    // Format nama error agar lebih rapi (contoh: not_full_up -> Not Full Up)
                    final errorName = entry.key.split('_').map((word) {
                      if (word.isEmpty) return '';
                      return word[0].toUpperCase() + word.substring(1);
                    }).join(' ');
                    
                    return Chip(
                      label: Text('$errorName: ${entry.value}', style: const TextStyle(color: Colors.white)),
                      backgroundColor: Colors.orangeAccent.withValues(alpha: 0.2),
                      side: const BorderSide(color: Colors.orangeAccent),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
              ],

              // AI Insight
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.psychology_outlined,
                        color: Colors.lightBlueAccent, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'AI Insight',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            result.insight,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Tombol Latihan Lagi
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigoAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.replay),
                label: const Text('Latihan Lagi',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  // Kembali ke home (pop semua sampai root)
                  Navigator.of(context).popUntil((r) => r.isFirst);
                },
                child: const Text('Kembali ke Home',
                    style: TextStyle(color: Colors.white38, fontSize: 14)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(value,
                style: TextStyle(
                    color: color,
                    fontSize: 22,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

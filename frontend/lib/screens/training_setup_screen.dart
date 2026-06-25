import 'package:flutter/material.dart';
import '../core/models/exercise_type.dart';
import 'training_screen.dart';

class TrainingSetupScreen extends StatefulWidget {
  final ExerciseType exerciseType;

  const TrainingSetupScreen({super.key, required this.exerciseType});

  @override
  State<TrainingSetupScreen> createState() => _TrainingSetupScreenState();
}

class _TrainingSetupScreenState extends State<TrainingSetupScreen> {
  int _targetReps = 10;
  final List<int> _repsOptions = [5, 10, 15, 20];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        title: const Text(
          'Setup Latihan',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF0D0D1A),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),

              // Tipe Latihan yang dipilih
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.fitness_center,
                      size: 48,
                      color: Colors.blueAccent,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Latihan Terpilih',
                      style: TextStyle(color: Colors.white54, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.exerciseType.displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 48),

              // Pilihan Target Reps
              const Text(
                'Target Repetisi:',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),

              Wrap(
                spacing: 12,
                runSpacing: 12,
                children:
                    _repsOptions.map((reps) {
                      final isSelected = _targetReps == reps;
                      return ChoiceChip(
                        label: Text(
                          '$reps Reps',
                          style: TextStyle(
                            color:
                                isSelected
                                    ? Colors.white
                                    : Colors.indigo.shade300,
                            fontWeight:
                                isSelected ? FontWeight.bold : FontWeight.bold,
                          ),
                        ),
                        selected: isSelected,
                        selectedColor: Colors.blueAccent,
                        backgroundColor: Colors.white.withValues(alpha: 0.1),
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _targetReps = reps;
                            });
                          }
                        },
                      );
                    }).toList(),
              ),

              const Spacer(),

              // Tombol Mulai
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder:
                          (context) => TrainingScreen(
                            exerciseType: widget.exerciseType,
                            targetReps: _targetReps,
                          ),
                    ),
                  );
                },
                icon: const Icon(Icons.play_arrow_rounded, size: 28),
                label: const Text(
                  'Mulai Latihan',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

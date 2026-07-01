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
  bool _isCustomReps = false;
  final TextEditingController _customRepsController = TextEditingController();

  @override
  void dispose() {
    _customRepsController.dispose();
    super.dispose();
  }

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
                                isSelected && !_isCustomReps
                                    ? Colors.white
                                    : Colors.indigo.shade300,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        selected: isSelected && !_isCustomReps,
                        selectedColor: Colors.blueAccent,
                        backgroundColor: Colors.white.withValues(alpha: 0.1),
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _targetReps = reps;
                              _isCustomReps = false;
                            });
                          }
                        },
                      );
                    }).toList()
                      ..add(
                        ChoiceChip(
                          label: Text(
                            'Custom',
                            style: TextStyle(
                              color: _isCustomReps ? Colors.white : Colors.indigo.shade300,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          selected: _isCustomReps,
                          selectedColor: Colors.blueAccent,
                          backgroundColor: Colors.white.withValues(alpha: 0.1),
                          onSelected: (selected) {
                            setState(() {
                              _isCustomReps = true;
                            });
                          },
                        ),
                      ),
              ),

              if (_isCustomReps) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _customRepsController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Masukkan Target Repetisi (1-100)',
                    labelStyle: const TextStyle(color: Colors.white54),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.white24),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.blueAccent),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (value) {
                    final intValue = int.tryParse(value);
                    if (intValue != null) {
                      _targetReps = intValue;
                    }
                  },
                ),
              ],

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
                  if (_isCustomReps) {
                    final val = int.tryParse(_customRepsController.text);
                    if (val == null || val < 1 || val > 100) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Masukkan angka valid antara 1 hingga 100'),
                          backgroundColor: Colors.redAccent,
                        ),
                      );
                      return;
                    }
                    _targetReps = val;
                  }
                  
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

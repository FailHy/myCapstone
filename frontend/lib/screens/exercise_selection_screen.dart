import 'package:flutter/material.dart';
import '../core/models/exercise_type.dart';
import 'training_setup_screen.dart';

class ExerciseSelectionScreen extends StatelessWidget {
  const ExerciseSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pilih Latihan'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Katalog Latihan',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text('Pilih rutinitas latihan Anda hari ini:'),
              const SizedBox(height: 32),
              
              _buildExerciseCard(
                context,
                title: ExerciseType.biceps.displayName,
                subtitle: 'Fokus pada otot lengan depan',
                icon: Icons.fitness_center,
                type: ExerciseType.biceps,
                colors: [Colors.blueAccent, Colors.lightBlue],
              ),
              const SizedBox(height: 20),
              
              _buildExerciseCard(
                context,
                title: ExerciseType.triceps.displayName,
                subtitle: 'Fokus pada otot lengan belakang',
                icon: Icons.sports_gymnastics,
                type: ExerciseType.triceps,
                colors: [Colors.indigo, Colors.deepPurple],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExerciseCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required ExerciseType type,
    required List<Color> colors,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TrainingSetupScreen(exerciseType: type),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24.0),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: Colors.white, size: 48),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 24),
              const Row(
                children: [
                  Text(
                    'Pilih Latihan',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}

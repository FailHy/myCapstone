import 'package:flutter/material.dart';
import '../core/models/exercise_type.dart';
import 'training_setup_screen.dart';
import '../theme.dart';

class ExerciseSelectionScreen extends StatelessWidget {
  const ExerciseSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgLightGrey,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Select Exercise',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        iconTheme: const IconThemeData(color: AppTheme.textDark),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTheme.spacing24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Exercise Catalog',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: AppTheme.spacing4),
              Text(
                'Choose your training routine for today',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppTheme.spacing32),

              _buildExerciseCard(
                context,
                title: ExerciseType.biceps.displayName,
                subtitle:
                    'High-intensity isolation for peak bicep development and arm strength.',
                type: ExerciseType.biceps,
                colors: [AppTheme.primaryBlue, const Color(0xFF0369A1)],
              ),
              const SizedBox(height: AppTheme.spacing20),

              _buildExerciseCard(
                context,
                title: ExerciseType.triceps.displayName,
                subtitle:
                    'Tricep-focused movements for comprehensive arm definition and power.',
                type: ExerciseType.triceps,
                colors: [AppTheme.secondaryBlue, const Color(0xFF1D4ED8)],
              ),

              const SizedBox(height: AppTheme.spacing32),

              // ── Info Card ──────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(AppTheme.spacing20),
                decoration: AppTheme.cardDecoration(),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppTheme.spacing8),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppTheme.radius8),
                      ),
                      child: const Icon(
                        Icons.info_outline_rounded,
                        color: AppTheme.primaryBlue,
                        size: AppTheme.iconMd,
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacing12),
                    Expanded(
                      child: Text(
                        'BiTri AI uses your device camera and ML-based pose detection to provide real-time form feedback during training.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
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
    required ExerciseType type,
    required List<Color> colors,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            PageRouteBuilder(
              pageBuilder: (_, __, ___) =>
                  TrainingSetupScreen(exerciseType: type),
              transitionsBuilder: (_, animation, __, child) =>
                  FadeTransition(opacity: animation, child: child),
              transitionDuration: const Duration(milliseconds: 250),
            ),
          );
        },
        borderRadius: BorderRadius.circular(AppTheme.radius20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppTheme.spacing24),
          decoration: AppTheme.gradientDecoration(colors: colors),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppTheme.spacing12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(AppTheme.radius12),
                    ),
                    child: Image.asset(
                      type.assetIcon,
                      width: 48,
                      height: 48,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.fitness_center_rounded,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacing12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(AppTheme.radius12),
                    ),
                    child: const Text(
                      'AI Guided',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spacing20),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: AppTheme.spacing8),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.88),
                ),
              ),
              const SizedBox(height: AppTheme.spacing20),
              Row(
                children: [
                  Text(
                    'Select Exercise',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: AppTheme.spacing8),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size: AppTheme.iconMd,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

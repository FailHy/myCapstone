import 'package:flutter/material.dart';
import '../core/models/exercise_type.dart';
import '../theme.dart';
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

  List<Color> get _gradientColors {
    return widget.exerciseType == ExerciseType.biceps
        ? [AppTheme.primaryBlue, const Color(0xFF0369A1)]
        : [AppTheme.secondaryBlue, const Color(0xFF1D4ED8)];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgLightGrey,
      appBar: AppBar(
        title: const Text('Setup Training'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.textDark),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacing24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Exercise Header Card ────────────────────────────────
              Container(
                padding: const EdgeInsets.all(AppTheme.spacing24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _gradientColors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(AppTheme.radius20),
                  boxShadow: [
                    BoxShadow(
                      color: _gradientColors.first.withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppTheme.spacing16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius:
                            BorderRadius.circular(AppTheme.radius16),
                      ),
                      child: Image.asset(
                        widget.exerciseType.assetIcon,
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
                    const SizedBox(width: AppTheme.spacing20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Selected Exercise',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: AppTheme.spacing4),
                          Text(
                            widget.exerciseType.displayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: AppTheme.spacing8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppTheme.spacing12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radius8),
                            ),
                            child: const Text(
                              'AI Powered',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppTheme.spacing32),

              // ── Target Reps Label ───────────────────────────────────
              Text(
                'Target Repetitions',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppTheme.spacing4),
              Text(
                'Choose how many reps you want to complete',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppTheme.spacing16),

              // ── Chip Grid ──────────────────────────────────────────
              Wrap(
                spacing: AppTheme.spacing12,
                runSpacing: AppTheme.spacing12,
                children: _repsOptions.map((reps) {
                  final isSelected = _targetReps == reps && !_isCustomReps;
                  return ChoiceChip(
                    label: Text(
                      '$reps Reps',
                      style: TextStyle(
                        color: isSelected
                            ? AppTheme.textLight
                            : AppTheme.primaryBlue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: AppTheme.primaryBlue,
                    backgroundColor: AppTheme.bgSoftBlue,
                    side: BorderSide(
                      color: isSelected
                          ? Colors.transparent
                          : AppTheme.primaryBlue.withValues(alpha: 0.4),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radius12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacing16,
                      vertical: AppTheme.spacing8,
                    ),
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
                          color: _isCustomReps
                              ? AppTheme.textLight
                              : AppTheme.primaryBlue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      selected: _isCustomReps,
                      selectedColor: AppTheme.primaryBlue,
                      backgroundColor: AppTheme.bgSoftBlue,
                      side: BorderSide(
                        color: _isCustomReps
                            ? Colors.transparent
                            : AppTheme.primaryBlue.withValues(alpha: 0.4),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radius12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.spacing16,
                        vertical: AppTheme.spacing8,
                      ),
                      onSelected: (selected) {
                        setState(() {
                          _isCustomReps = true;
                        });
                      },
                    ),
                  ),
              ),

              if (_isCustomReps) ...[
                const SizedBox(height: AppTheme.spacing16),
                TextField(
                  controller: _customRepsController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: AppTheme.textDark),
                  decoration: const InputDecoration(
                    labelText: 'Enter Target Reps (1–100)',
                    prefixIcon: Icon(Icons.edit_outlined),
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

              // ── Start Button ───────────────────────────────────────
              ElevatedButton.icon(
                onPressed: () {
                  if (_isCustomReps) {
                    final val = int.tryParse(_customRepsController.text);
                    if (val == null || val < 1 || val > 100) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Please enter a valid number between 1 and 100',
                          ),
                          backgroundColor: AppTheme.error,
                        ),
                      );
                      return;
                    }
                    _targetReps = val;
                  }

                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => TrainingScreen(
                        exerciseType: widget.exerciseType,
                        targetReps: _targetReps,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.play_arrow_rounded, size: 26),
                label: const Text('Start Training'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, AppTheme.buttonHeight),
                ),
              ),
              const SizedBox(height: AppTheme.spacing16),
            ],
          ),
        ),
      ),
    );
  }
}

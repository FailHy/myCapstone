enum ExerciseType {
  biceps,
  triceps,
}

extension ExerciseTypeExt on ExerciseType {
  String get displayName {
    switch (this) {
      case ExerciseType.biceps:
        return 'Biceps Curl';
      case ExerciseType.triceps:
        return 'Triceps Extension';
    }
  }

  String get backendCode {
    // Enum name automatically matches backend requirements ("biceps", "triceps")
    return name;
  }
}

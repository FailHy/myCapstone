enum ExerciseType {
  biceps,
  triceps;

  String get displayName {
    switch (this) {
      case ExerciseType.biceps:
        return 'Biceps Curl';
      case ExerciseType.triceps:
        return 'Triceps Extension';
    }
  }

  String get backendCode {
    return name;
  }

  String get assetIcon {
    switch (this) {
      case ExerciseType.biceps:
        return 'assets/images/Biceps icon.png';
      case ExerciseType.triceps:
        return 'assets/images/Triceps icon.png';
    }
  }
}

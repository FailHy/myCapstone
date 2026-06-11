# BiTri AI

## Project Overview

BiTri AI is a cross-platform fitness application built with Flutter that uses AI-powered movement evaluation to help users train with correct form. The frontend supports Android, iOS, Web, Linux, macOS, and Windows from a single Dart codebase. A Python backend (located in `myproject/`) handles AI inference and API services.

## Tech Stack

- Flutter: >=3.18.0
- Dart SDK: ^3.7.2
- cupertino_icons: ^1.0.8
- flutter_lints: ^5.0.0
- Python: >=3.10 (backend)
- Gradle: 8.10.2 (Android build)
- Kotlin: 1.8.22 (Android runner)
- Swift: 5.0 (iOS/macOS runner)

## Prerequisites

- Flutter SDK >= 3.18.0 installed and in `PATH`
- Dart SDK ^3.7.2 (bundled with Flutter)
- Android Studio or Xcode for mobile targets
- Python >= 3.10 with `pip` for the backend
- Git

Verify Flutter setup:

```bash
flutter doctor
```

## Installation

Clone the repository:

```bash
git clone {{REPO_URL}}
cd {{REPO_ROOT}}
```

Install Flutter dependencies:

```bash
cd frontend
flutter pub get
```

Install Python backend dependencies:

```bash
cd ../myproject
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

## Environment Variables

| Variable | Description | Default | Required |
|---|---|---|---|
| `API_BASE_URL` | Backend API base URL consumed by the Flutter app | `http://localhost:8000` | Yes |
| `ML_MODEL_PATH` | Absolute path to the pose estimation model file | `models/pose_model.tflite` | Yes |
| `SECRET_KEY` | Secret key for JWT signing (backend) | — | Yes |
| `DATABASE_URL` | Database connection string (backend) | `sqlite:///db.sqlite3` | No |
| `DEBUG` | Enable debug mode in backend (`true`/`false`) | `false` | No |

Create a `.env` file in `myproject/` before running the backend:

```bash
cp myproject/.env.example myproject/.env
# Edit myproject/.env and fill in the required values
```

## Usage

Run the Flutter app on a connected device or emulator:

```bash
cd frontend
flutter run
```

Run on a specific platform explicitly:

```bash
flutter run -d android
flutter run -d ios
flutter run -d chrome
flutter run -d linux
```

Start the Python backend:

```bash
cd myproject
source venv/bin/activate
python main.py
```

The app entry point is `frontend/lib/main.dart`. The initial route is `/login`, which navigates to `/main` (Home + BottomNav) after authentication.

## Project Structure

```
.
├── frontend/                        # Flutter application
│   ├── lib/
│   │   ├── main.dart                # App entry point, route definitions
│   │   ├── theme.dart               # Global ThemeData (dark navy + lime)
│   │   ├── screens/
│   │   │   ├── login_screen.dart    # Login UI
│   │   │   ├── main_navigation.dart # BottomNavigationBar shell
│   │   │   ├── home_screen.dart     # Training card list
│   │   │   ├── training_screen.dart # Camera + rep counter + ML integration point
│   │   │   ├── result_screen.dart   # AI insights + rep results
│   │   │   └── profile_screen.dart  # User stats + history
│   │   └── widgets/
│   │       └── custom_widgets.dart  # PrimaryButton, TrainingCard, StatsCard
│   ├── test/
│   │   └── widget_test.dart
│   ├── android/                     # Android runner
│   ├── ios/                         # iOS runner
│   ├── macos/                       # macOS runner
│   ├── linux/                       # Linux runner
│   ├── windows/                     # Windows runner
│   ├── web/                         # Web runner
│   └── pubspec.yaml
├── myproject/                       # Python backend
│   ├── main.py                      # Backend entry point
│   ├── requirements.txt
│   └── .env.example
└── README.md
```

## API Endpoints

The Flutter frontend communicates with the Python backend over HTTP. All endpoints are prefixed with `/api/v1`.

### Authentication

```
POST /api/v1/auth/login
```

Request body:

```json
{
  "email": "user@example.com",
  "password": "{{PASSWORD}}"
}
```

Response:

```json
{
  "access_token": "eyJ...",
  "token_type": "Bearer"
}
```

### Pose Evaluation

```
POST /api/v1/evaluate
Authorization: Bearer {{ACCESS_TOKEN}}
Content-Type: application/json
```

Request body:

```json
{
  "exercise": "bicep_curl",
  "keypoints": [[0.5, 0.3], [0.6, 0.4]]
}
```

Response:

```json
{
  "correct_reps": 8,
  "incorrect_reps": 2,
  "feedback": ["Keep elbows tucked in during curls."]
}
```

## Testing

Run Flutter widget tests:

```bash
cd frontend
flutter test
```

Run Flutter tests with coverage:

```bash
cd frontend
flutter test --coverage
```

Run Python backend tests:

```bash
cd myproject
source venv/bin/activate
pytest
```

Run Python tests with verbose output:

```bash
pytest -v
```

Note: `frontend/test/widget_test.dart` references `MyApp` which is the default counter app class. Update this file to reference `BiTriApp` after verifying the integration test scope.

## Deployment

### Android (Release APK)

```bash
cd frontend
flutter build apk --release
```

The output APK is located at `frontend/build/app/outputs/flutter-apk/app-release.apk`.

### Android (App Bundle for Play Store)

```bash
cd frontend
flutter build appbundle --release
```

### iOS (Archive for App Store)

```bash
cd frontend
flutter build ios --release
open ios/Runner.xcworkspace
```

Use Xcode Organizer to archive and upload to App Store Connect.

### Web

```bash
cd frontend
flutter build web --release
```

Serve the output from `frontend/build/web/` using any static file host (Nginx, Firebase Hosting, etc.).

### Backend

```bash
cd myproject
source venv/bin/activate
pip install gunicorn
gunicorn main:app --bind 0.0.0.0:8000 --workers 4
```

To containerize the backend:

```bash
docker build -t bitri-backend ./myproject
docker run -p 8000:8000 --env-file myproject/.env bitri-backend
```

## Troubleshooting

**Problem:** `flutter run` fails with `flutter.sdk not set in local.properties`

Cause: The Android SDK path is not configured for the current machine.

Solution:

```bash
cd frontend/android
echo "flutter.sdk=$(which flutter | sed 's|/bin/flutter||')" >> local.properties
echo "sdk.dir={{ANDROID_SDK_PATH}}" >> local.properties
```

---

**Problem:** `Gradle build failed` with `Xmx` heap error on Android

Cause: The default JVM heap size is insufficient.

Solution: The `frontend/android/gradle.properties` file already sets `-Xmx8G`. If the build still fails, reduce it to `-Xmx4G` if the host machine has less than 8 GB of available RAM:

```bash
sed -i 's/-Xmx8G/-Xmx4G/' frontend/android/gradle.properties
```

---

**Problem:** Backend returns `500 Internal Server Error` on `/api/v1/evaluate`

Cause: The ML model file is missing or `ML_MODEL_PATH` is incorrect.

Solution: Verify the model file exists at the path set in `.env` and that the backend process has read permission:

```bash
ls -lh $(grep ML_MODEL_PATH myproject/.env | cut -d= -f2)
```

---

**Problem:** Camera preview does not appear on the Training screen

Cause: The `TrainingScreen` uses a placeholder `Container(color: Colors.black)`. Camera integration requires the `camera` Flutter plugin, which is not yet added to `pubspec.yaml`.

Solution: Add the camera dependency and implement the `TODO` in `frontend/lib/screens/training_screen.dart`:

```bash
cd frontend
flutter pub add camera
```

Then replace the placeholder container with a `CameraPreview` widget.

## AI Instructions

```json
{
  "project": "BiTri AI",
  "entry_point": "frontend/lib/main.dart",
  "initial_route": "/login",
  "routes": ["/login", "/main", "/training", "/result"],
  "theme": {
    "primary_color": "#0B0F2F",
    "accent_color": "#D6FF3F",
    "surface_color": "#1A1F4C"
  },
  "backend_entry": "myproject/main.py",
  "backend_port": 8000,
  "install_steps": [
    "flutter pub get (in frontend/)",
    "pip install -r requirements.txt (in myproject/)",
    "copy .env.example to .env and fill values"
  ],
  "known_todos": [
    "Integrate camera plugin in training_screen.dart",
    "Connect WebSocket for real-time ML pose estimation",
    "Replace hardcoded user data with API calls",
    "Fix widget_test.dart to reference BiTriApp instead of MyApp"
  ],
  "validation_regex": {
    "email": "^[\\w\\.-]+@[\\w\\.-]+\\.\\w+$",
    "api_url": "^https?:\\/\\/[\\w\\.-]+(:\\d+)?(\\/.*)?$"
  }
}
```

## Contributors

1. Fork the repository.
2. Create a feature branch from `main`: `git checkout -b feat/{{FEATURE_NAME}}`.
3. Follow the existing code style: all Dart files use the `flutter_lints` ruleset defined in `frontend/analysis_options.yaml`.
4. Add or update widget tests for any new screen or widget in `frontend/test/`.
5. Verify no lint warnings: `flutter analyze`.
6. Submit a pull request against `main` with a description of what was changed and why.
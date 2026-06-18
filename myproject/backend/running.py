import sys
from pathlib import Path

# Pastikan project root ada di sys.path
PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

import uvicorn

if __name__ == "__main__":
    # Runs the app on http://0.0.0.0:8000
    # reload=True is great for development (auto-restarts on save)
    uvicorn.run("backend.api.main:app", host="0.0.0.0", port=8000, reload=True)
# Capture - Screenshot to Calendar Event

An iOS app that lets you take screenshots of events and automatically creates calendar entries using AI.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         iOS App                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │ Google Auth │  │  Home View  │  │   iOS Shortcut Setup    │  │
│  │   (OAuth)   │  │  (SwiftUI)  │  │  (Take Screenshot →     │  │
│  │             │  │             │  │   Send to Backend)      │  │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      FastAPI Backend                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │   /analyze-     │  │   OpenAI        │  │   Google        │  │
│  │   screenshot    │→ │   Vision API    │→ │   Calendar API  │  │
│  │   endpoint      │  │   (GPT-4o)      │  │                 │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Setup

### Prerequisites

- Xcode 15+
- Python 3.10+
- Google Cloud Console account
- OpenAI API key

### 1. Google Cloud Setup

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select existing
3. Enable the following APIs:
   - Google Calendar API
   - Google People API (for user info)
4. Create OAuth 2.0 credentials:
   - Application type: iOS
   - Bundle ID: `com.yourcompany.CaptureMobile`
5. Note down the **Client ID**

### 2. iOS App Setup

1. Open `CaptureMobile/CaptureMobile.xcodeproj` in Xcode

2. Add Google Sign-In SDK:
   - File → Add Package Dependencies
   - URL: `https://github.com/google/GoogleSignIn-iOS`
   - Add `GoogleSignIn` and `GoogleSignInSwift`

3. Update `Info.plist`:
   - Replace `YOUR_GOOGLE_CLIENT_ID` with your actual Client ID
   - Replace `YOUR_CLIENT_ID_HERE` in the URL scheme with the reversed Client ID

4. Build and run on a device/simulator

### 3. Backend Setup

```bash
cd backend

# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Configure environment
cp env.example .env
# Edit .env and add your API keys

# Run the server
python main.py
```

The server will start at `http://localhost:8000`

### 4. Configure Backend URL

Update the backend URL in:
- `CaptureMobile/CaptureMobile/APIService.swift` → `baseURL`
- `CaptureMobile/CaptureMobile/ShortcutManager.swift` → `backendURL`

For production, deploy to a server with HTTPS.

## Environment Variables

| Variable | Description |
|----------|-------------|
| `OPENAI_API_KEY` | Your OpenAI API key (needs GPT-4 Vision access) |
| `GOOGLE_CLIENT_ID` | Google OAuth Client ID for token validation |
| `HOST` | Server host (default: 0.0.0.0) |
| `PORT` | Server port (default: 8000) |
| `DEBUG` | Enable debug mode (default: false) |

## API Endpoints

### `GET /health`
Health check endpoint.

### `POST /analyze-screenshot`
Analyze a screenshot and create a calendar event.

**Request Body:**
```json
{
  "image": "base64_encoded_image_data",
  "access_token": "google_oauth_access_token"
}
```

**Response:**
```json
{
  "success": true,
  "event_created": {
    "id": "event_id",
    "title": "Team Meeting",
    "start_time": "2026-01-20T10:00:00",
    "end_time": "2026-01-20T11:00:00",
    "location": "Conference Room A",
    "description": "Weekly sync",
    "calendar_link": "https://calendar.google.com/..."
  },
  "message": "Event 'Team Meeting' created successfully!"
}
```

## Usage

1. Sign in with Google in the app
2. Tap "Setup iOS Shortcut" to create the capture shortcut
3. When you see an event you want to capture:
   - Run the shortcut (from Home Screen, Shortcuts app, or Action Button)
   - Or take a screenshot and share it to the Capture app
4. The AI analyzes the screenshot and creates the event in your calendar

## Project Structure

```
Capture/
├── CaptureMobile/           # iOS App
│   └── CaptureMobile/
│       ├── CaptureMobileApp.swift
│       ├── ContentView.swift
│       ├── AuthView.swift
│       ├── HomeView.swift
│       ├── ShortcutSetupView.swift
│       ├── GoogleAuthManager.swift
│       ├── KeychainHelper.swift
│       ├── ShortcutManager.swift
│       ├── APIService.swift
│       └── Info.plist
│
├── backend/                  # Python Backend
│   ├── main.py
│   ├── requirements.txt
│   ├── env.example
│   ├── models/
│   │   └── schemas.py
│   └── services/
│       ├── openai_service.py
│       └── calendar_service.py
│
└── README.md
```

## License

MIT

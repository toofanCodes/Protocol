# Protocol Analytics Web Dashboard

A web-based analytics platform for Protocol habit tracking data.

## Setup

### Prerequisites
- Node.js 18+
- Firebase CLI (`npm install -g firebase-tools`)
- Google Cloud Project with Drive API enabled
- Firebase project

### Installation

1. Install dependencies:
```bash
cd analytics-web
npm install
```

2. Configure Google OAuth:
   - Go to [Google Cloud Console](https://console.cloud.google.com/)
   - Create/select project
   - Enable Google Drive API
   - Create OAuth 2.0 credentials (Web application)
   - Add authorized JavaScript origin: `http://localhost:5173` (for dev) and your Firebase domain
   - Copy Client ID and API Key to `src/auth.js`

3. Configure Firebase:
   - Run `firebase login`
   - Run `firebase init` (select Hosting)
   - Update `.firebaserc` with your project ID

4. Configure Gemini API (for Phase 5):
   - Get API key from [Google AI Studio](https://makersuite.google.com/app/apikey)
   - Add to `src/query.js`

### Development

```bash
npm run dev
```

Opens at `http://localhost:5173`

### Deployment

```bash
npm run deploy
```

## Architecture

- **Auth**: Google OAuth via Google API client
- **Sync**: Downloads JSON files from Google Drive, caches in IndexedDB
- **Query**: LLM-powered natural language queries (Phase 5)
- **Viz**: Chart.js charts (Phase 4)

## Current Status

Phase 1 (Foundation) complete:
- ✅ Project structure
- ✅ Firebase configuration
- ✅ Auth scaffolding
- ✅ Sync scaffolding
- ⏳ Need to add Google credentials

Next: Configure auth credentials and test Drive API connection.

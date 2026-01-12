# Analytics Web (Work In Progress)

**⚠️ This project is currently under development and is not yet ready for production use.**

This directory contains a web-based library for displaying analytics for the Protocol app.

## Security Configuration

This project contains placeholder API keys in the source code for setup purposes. **Do not replace these placeholders directly.**

To configure the project for local development, create a new file named `.env.local` in this directory. This file is included in `.gitignore` and will not be committed.

Your `.env.local` file should contain your development keys:

```
VITE_GAPI_CLIENT_ID=YOUR_CLIENT_ID_HERE.apps.googleusercontent.com
VITE_GAPI_API_KEY=YOUR_API_KEY_HERE
VITE_GEMINI_API_KEY=YOUR_GEMINI_API_KEY_HERE
```

The application will load these variables at runtime.
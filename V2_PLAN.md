# Protocol V2 Plan: Bio Tracker with Fitbit Integration

> **Status:** On Hold  
> **Created:** January 2026  
> **Goal:** Transform Protocol from a data recorder to a bio tracker with Fitbit API integration

---

## Overview

Version 2.0 will integrate Fitbit API data against exercises and habits, enabling users to correlate their logged activities with real biometric data (heart rate, steps, sleep, etc.).

---

## Versioning Strategy

### Git
- [ ] Tag current stable state as `v1.0.0`
- [ ] Create `feature/fitbit-integration` branch

### App Version
- Bump to `2.0.0` when integration is complete

### SwiftData Schema
- Implement `VersionedSchema` for backward compatibility
- Add new models: `FitbitSync`, `BiometricReading`, etc.

---

## High-Level Features

1. **Fitbit OAuth Integration**
   - OAuth 2.0 flow for user authentication
   - Secure token storage in Keychain

2. **Data Sync**
   - Pull heart rate, steps, sleep, and activity data
   - Background refresh support

3. **Correlation Engine**
   - Link Fitbit data to `Habit` and `Molecule` entries
   - Visualize biometric trends against habit completion

4. **Settings Expansion**
   - Fitbit account connection/disconnection
   - Sync frequency preferences
   - Feature flag: `@AppStorage("fitbitIntegrationEnabled")`

---

## Technical Considerations

- **API Limits:** Fitbit has rate limits (150 requests/hour)
- **Privacy:** Handle health data per Apple's guidelines
- **Offline Support:** Cache synced data locally

---

## Resources

- [Fitbit Web API Documentation](https://dev.fitbit.com/build/reference/web-api/)
- [OAuth 2.0 for iOS](https://developer.apple.com/documentation/authenticationservices)

---

## AI/LLM Chatbot Integration (Gemini API)

> **Priority:** Future  
> **Prerequisite:** Analytics Query Layer must be implemented first

### Overview

Add an in-app conversational assistant powered by Gemini LLM API that can answer questions about habits, provide insights, and offer personalized recommendations.

### ChatDataProvider Service

A new service that extracts and summarizes user data for LLM context:

```swift
@MainActor
class ChatDataProvider {
    private let modelContext: ModelContext
    
    // Context extraction methods:
    func recentActivitySummary(days: Int = 7) async -> String
    func habitPerformanceContext(habitId: UUID) async -> String
    func upcomingScheduleContext() async -> String
    func streakAndConsistencyContext() async -> String
    
    // Token-efficient summaries (prevents context overflow):
    func compressedHistorySummary(maxTokens: Int = 2000) async -> String
}
```

### Data Points to Expose

| Data Category | Example Output |
|---------------|----------------|
| Recent completions | "Last 7 days: 23/28 habits completed (82%)" |
| Top/bottom performers | "Strongest: Morning Run (95%), Weakest: Reading (40%)" |
| Streaks | "Current streak: 12 days. Best ever: 34 days." |
| Time patterns | "Most productive time: 7-9 AM" |
| Upcoming items | "Today: 4 remaining. Tomorrow: 6 scheduled." |

### API Integration

- **Endpoint:** Gemini API (`generativelanguage.googleapis.com`)
- **Auth:** API key stored in Keychain (not hardcoded)
- **Rate Limits:** Respect per-minute quotas
- **Privacy:** User must opt-in; no data leaves device without consent

### UI Concept

- Chat bubble accessible from Settings or a dedicated tab
- Pre-built quick prompts: "How am I doing this week?", "What should I focus on?"
- Conversational UI with message history (stored locally)

---

*This plan will be revisited when V1 is stable and ready for expansion.*

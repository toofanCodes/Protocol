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

*This plan will be revisited when V1 is stable and ready for expansion.*

# Protocol QA Checklist

> Pre-release manual testing checklist. Complete all items before App Store submission.
> **Priority Focus: Data Integrity & Security**

---

## 🛡️ DATA LOSS PREVENTION (Critical)

### Delete Operations
- [ ] Delete molecule → **past history preserved** (check Insights still shows data)
- [ ] Delete molecule → only future instances removed
- [ ] Force-quit during delete → no partial/corrupt state
- [ ] Bulk delete atoms → parent molecule still intact
- [ ] Archive and unarchive → all data restored exactly

### Orphan Prevention
- [ ] Delete template → no orphan instances created
- [ ] Check Lost & Found after bulk operations (should be empty)
- [ ] Manually corrupt relationship → recovery works (via DataController)

### Crash Recovery
- [ ] Force-quit mid-save → data not lost on relaunch
- [ ] Low memory kill → state preserved
- [ ] Power off during backup → database not corrupted
- [ ] App crashes during migration → graceful recovery

### Backup Integrity
- [ ] **Create backup → immediately restore → all data matches exactly**
- [ ] Backup file can be opened after app reinstall
- [ ] Backup from older version restores correctly
- [ ] Large backup (1000+ instances) completes without timeout
- [ ] Corrupted backup file shows error, doesn't crash

### Sync Boundary
- [ ] Widget and main app show same data
- [ ] Complete in widget → main app reflects change
- [ ] Complete in main app → widget updates
- [ ] No race conditions with simultaneous edits

---

## 🔒 DATA LEAK PREVENTION (Critical)

### File Protection
- [ ] Database files have `.completeUntilFirstUserAuthentication` protection
- [ ] Backup files have `.completeFileProtection`
- [ ] No sensitive data in app logs (check Xcode console)
- [ ] No PII in crash reports

### App Sandbox
- [ ] `Protocol.sqlite` only in App Group container
- [ ] No files written to shared locations (Documents, tmp visible to user)
- [ ] Share sheet only exports `.protocolbackup` files

### Network Isolation (Offline-First)
- [ ] **Airplane mode → app fully functional**
- [ ] No outbound network requests (use Network Link Conditioner)
- [ ] No analytics/tracking SDKs present
- [ ] Google Sign-In only if user initiates

### Extension Isolation
- [ ] Widget cannot access main app's non-shared data
- [ ] Notification extension has minimal data access
- [ ] Share extension (if any) sandboxed properly

### Debug Builds
- [ ] `print()` statements suppressed in Release builds
- [ ] Audit logs don't contain sensitive field values
- [ ] No hardcoded test data in production bundle

---

## 🆕 Fresh Install

- [ ] App launches without crash on clean install
- [ ] Onboarding flow completes successfully
- [ ] Default protocols are seeded (if enabled)
- [ ] Notifications permission prompt appears
- [ ] Widget can be added to home screen

## 📦 Molecule CRUD

- [ ] Create new molecule with title, time, and recurrence
- [ ] Add multiple atoms to a molecule
- [ ] Edit molecule title and time
- [ ] Delete molecule (verify future instances removed, history preserved)
- [ ] Duplicate molecule creates independent copy
- [ ] Archived molecules hidden from main list

## ✅ Completion Flow

- [ ] Tap molecule to complete → all atoms marked complete
- [ ] Tap to uncomplete → all atoms unmarked
- [ ] Complete individual atoms → parent auto-completes when all done
- [ ] Uncomplete one atom → parent uncompletes
- [ ] Streaks update correctly after completion
- [ ] Celebrations trigger (confetti, sound)

## 🔔 Notifications

- [ ] Notifications fire at scheduled time
- [ ] Multiple alert offsets work (15m, 1h before)
- [ ] Completing a molecule cancels its pending notifications
- [ ] Snoozing reschedules notification correctly
- [ ] All-day molecules have appropriate notification behavior

## 📱 Widget

- [ ] Widget shows today's upcoming molecules
- [ ] Widget updates after completing in app
- [ ] Tapping widget item opens correct molecule
- [ ] Widget respects all-day vs timed display

## 📊 Analytics (Insights)

- [ ] Weekly bar chart displays correctly
- [ ] Monthly heatmap shows completion colors
- [ ] Time range navigation works (arrows, Today button)
- [ ] Stats calculate correctly (streaks, consistency)

## 📥 CSV Import (Blueprint Architect)

- [ ] Import valid CSV creates molecules and atoms
- [ ] Invalid CSV shows appropriate error
- [ ] Duplicate detection works correctly
- [ ] **Malformed CSV doesn't corrupt existing data**

## 🌐 Edge Cases

- [ ] Timezone change handling (travel scenario)
- [ ] App backgrounded 24+ hours → background refresh works
- [ ] Device restart → notifications still scheduled
- [ ] Low storage → app handles gracefully
- [ ] Database migration from previous version works
- [ ] Date set to past/future → app handles gracefully

---

## 🧪 Automated Test Verification

Before release, run full test suite:
```
Cmd+U in Xcode
```

All tests must pass:
- [ ] AuditLoggerTests (12)
- [ ] DataControllerRecoveryTests (3)
- [ ] BackupManagerTests (7)
- [ ] MoleculeServiceTests (7)
- [ ] ModelTests (18)

---

## Sign-Off

| Tester | Date | Build | Notes |
|--------|------|-------|-------|
|        |      |       |       |

**Release Blocker**: Any failure in "DATA LOSS PREVENTION" or "DATA LEAK PREVENTION" sections = NO RELEASE.

---

## 🛠️ Structural Findings (Post-Audit)

### Architecture & Pattern Violations
- [x] **MVVM Violation**: `AuditLogViewer` contains filtering logic (`filteredEntries`) that belongs in a ViewModel. (Refactored to `AuditLogViewModel`)
- [x] **Hard Dependency**: `AuditLogViewer` relies directly on `AuditLogger.shared`, making isolation testing difficult. (ViewModel now accepts dependency injection)
- [ ] **Singleton Pattern**: Widespread use of `AuditLogger.shared` complicates parallel testing. (Reduced in View, still default in VM)

### Performance & Concurrency
- [x] **Blocking I/O**: `AuditLogger` (Actor) performs synchronous file I/O (`data.write`) inside async methods. (Moved to background queue)
- [ ] **Test Flakiness**: `AuditLoggerTests` relies on `Task.sleep` for ordering verification.

### Security & Data Integrity
- [x] **Missing File Protection**: `audit_log.json` is saved without explicit `.completeUntilFirstUserAuthentication` or `.completeFileProtection`. (Added `.completeUntilFirstUserAuthentication`)

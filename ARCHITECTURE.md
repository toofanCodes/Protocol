# Protocol — Architecture

> Last Updated: January 2026 | Schema Version: 1.0.0

## Overview

Protocol is a native iOS habit tracking app built with **SwiftUI** and **SwiftData**. It uses a "Molecule → Atom" metaphor where routines (Molecules) contain individual tasks (Atoms).

---

## Project Structure

```
Protocol/
├── Protocol/                     # Main App Target
│   ├── Data/                     # Data Layer
│   │   ├── AppMigrationPlan.swift   # Schema versioning
│   │   ├── DataController.swift     # ModelContainer setup
│   │   └── SchemaVersions.swift     # Legacy reference
│   ├── Models/                   # SwiftData Models
│   │   ├── MoleculeTemplate.swift   # Recurring routine definition
│   │   ├── MoleculeInstance.swift   # Single occurrence
│   │   ├── AtomTemplate.swift       # Task blueprint
│   │   ├── AtomInstance.swift       # Task occurrence
│   │   ├── WorkoutSet.swift         # Exercise tracking
│   │   ├── UserSettings.swift       # App preferences
│   │   ├── AppMetadata.swift        # JSON config helper
│   │   └── RecurrenceTypes.swift    # Enums
│   ├── Views/                    # UI Components
│   ├── Helpers/                  # Services & Managers
│   └── ProtocolApp.swift         # App Entry Point
├── ProtocolWidget/               # Widget Extension
├── ProtocolTests/                # Unit Tests
└── Protocol.xcodeproj
```

---

## Data Model

```mermaid
erDiagram
    MoleculeTemplate ||--o{ MoleculeInstance : generates
    MoleculeTemplate ||--o{ AtomTemplate : contains
    MoleculeInstance ||--o{ AtomInstance : contains
    AtomInstance ||--o{ WorkoutSet : tracks
    UserSettings ||--|| AppMetadata : stores
```

### Core Models

| Model | Purpose |
|-------|---------|
| `MoleculeTemplate` | Defines a recurring routine (title, schedule, alerts) |
| `MoleculeInstance` | A single occurrence of a routine on a specific date |
| `AtomTemplate` | Blueprint for a task within a routine |
| `AtomInstance` | A task occurrence with completion status |
| `WorkoutSet` | Individual set data for exercise atoms |
| `UserSettings` | App-wide preferences with JSON metadata |

### Flexible Metadata Pattern

`UserSettings.metadataJSON` stores a `Codable` struct (`AppMetadata`) as JSON. This allows adding new preferences without database migrations.

```swift
let settings = UserSettings.current(in: context)
settings.updateMetadata { $0.theme = .dark }
```

---

## Schema Migration

We use **SwiftData's VersionedSchema** for safe migrations:

```swift
enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [...] }
}

enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
```

**Adding a new schema version:**
1. Create `SchemaV2` with updated models.
2. Add a migration stage to `AppMigrationPlan.stages`.
3. Update `schemas` to include both versions.

---

## Key Services

| Service | File | Responsibility |
|---------|------|----------------|
| `DataController` | `DataController.swift` | Manages `ModelContainer`, handles recovery |
| `MoleculeService` | `MoleculeService.swift` | CRUD for molecules, instance generation |
| `NotificationManager` | `NotificationManager.swift` | Local notifications scheduling |
| `BackgroundScheduler` | `BackgroundScheduler.swift` | Background refresh tasks |
| `OnboardingManager` | `OnboardingManager.swift` | First-launch seeding |

---

## Widget

The **ProtocolWidget** displays today's upcoming molecules. It shares the same data layer via App Group:

- **App Group**: `group.com.Toofan.Toofanprotocol.shared`
- **Shared Files**: `DataController`, `AppMigrationPlan`, all Models

---

## Testing

| Test File | Coverage |
|-----------|----------|
| `DataControllerRecoveryTests.swift` | Database corruption recovery |

Run tests: **Cmd+U** in Xcode.

---

## Build Tags

| Tag | Description |
|-----|-------------|
| `stable-migration-v1` | Pre-cleanup baseline after migration fix |

---

## Security & Privacy

- **No Analytics**: Zero third-party tracking.
- **Offline First**: All data stored locally via SwiftData.
- **No Network**: App does not make any network requests.

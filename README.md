# Protocol

> **Build Your Empire, One Habit at a Time.**

Protocol is a native iOS application designed to help users build **compound routines**. Unlike traditional habit trackers that treat goals as isolated checkboxes, Protocol organizes them into systems ("Molecules") composed of individual actions ("Atoms").

![Platform](https://img.shields.io/badge/Platform-iOS%2017+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![SwiftData](https://img.shields.io/badge/Data-SwiftData-green)
![Widget](https://img.shields.io/badge/Widget-WidgetKit-purple)

---

## 🧪 Core Concepts

| Concept | Description |
|---------|-------------|
| **Molecule** | A complete routine (e.g., "Morning Protocol") scheduled at a specific time |
| **Atom** | A single task inside a Molecule (e.g., "Drink Water", "Read 10 mins") |
| **Instance** | A specific occurrence of a Molecule on a given date |
| **Compound Growth** | Consistent execution builds streaks and momentum |

---

## ✨ Features

- 📦 **Contextual Tracking** — Group related habits into powerful routines
- ⏰ **Smart Reminders** — Multiple alerts per routine (15 min, 1 hour, etc.)
- 📱 **Home Screen Widget** — View and complete tasks directly from home screen
- 💾 **Offline First** — All data stored locally with SwiftData
- 📊 **Insights** — Visual dashboards for streaks and completion history
- 🏋️ **Workout Tracking** — Sets, reps, weight logging for exercise atoms
- 🎨 **All-Day Events** — Support for habits without specific times

---

## 🛠 Tech Stack

| Layer | Technology |
|-------|------------|
| **UI** | SwiftUI |
| **Data** | SwiftData with VersionedSchema |
| **Widgets** | WidgetKit |
| **Background** | BGTaskScheduler |
| **Notifications** | UserNotifications (Local) |

---

## 🚀 Getting Started

### Prerequisites
- Xcode 15+
- iOS 17+ Simulator or Device

### Installation

```bash
git clone https://github.com/yourusername/protocol.git
cd protocol
open Protocol.xcodeproj
```

### Configuration

The app uses App Groups for widget data sharing:
- **App Group ID**: `group.com.Toofan.Toofanprotocol.shared`

Ensure both targets (Protocol and ProtocolWidgetExtension) have this capability enabled.

---

## 🏗 Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed documentation.

### Quick Overview

```
Protocol/
├── Protocol/           # Main App
│   ├── Data/           # DataController, Migration Plan
│   ├── Models/         # SwiftData @Model classes
│   ├── Views/          # SwiftUI Views
│   └── Helpers/        # Services & Managers
├── ProtocolWidget/     # Home Screen Widget
└── ProtocolTests/      # Unit Tests
```

### Data Model

```
MoleculeTemplate → MoleculeInstance → AtomInstance → WorkoutSet
                 ↳ AtomTemplate
```

---

## 🧪 Testing

```bash
# Run all tests
xcodebuild test -scheme Protocol -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

Or press **Cmd+U** in Xcode.

---

## 🔒 Privacy

Protocol is **privacy-first**:
- ✅ No analytics or tracking
- ✅ No network requests
- ✅ All data stays on-device
- ✅ No accounts required

---

## 🤖 AI-Assisted Development

This is an endeavour to make use of AI tools to improve productivity. Technologies used Gemini CLI, Claude Opus, and Gemini 3 where Gemini CLI did the versioning and file management, Gemini 3 did much of the building, while Opus developed PRD's and test/unit cases for the app. All this was done in Antigravity IDE of Google.

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🏷 Version History

| Version | Date | Notes |
|---------|------|-------|
| 1.0.0 | Jan 2026 | Initial release with migration safety |
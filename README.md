# Protocol

> **Build Your Empire, One Habit at a Time.**

Protocol is a native iOS application designed to help users build **compound routines**. Unlike traditional habit trackers that treat goals as isolated checkboxes, Protocol organizes them into systems ("Molecules") composed of individual actions ("Atoms").

![Platform](https://img.shields.io/badge/Platform-iOS-blue)
![Lang](https://img.shields.io/badge/Language-Swift%205-orange)
![Stack](https://img.shields.io/badge/Stack-SwiftUI%20%7C%20SwiftData%20%7C%20WidgetKit-green)

---

## 🧪 Concepts

- **Molecule**: A complete routine (e.g., "Morning Protocol"). Scheduled at a specific time.
- **Atom**: A single atomic unit of work inside a Molecule (e.g., "Drink Water", "Read 10 mins").
- **Compound Growth**: Consistent execution of Atoms builds streaks and momentum for the parent Molecule.

## ✨ Features

- **Contextual Tracking**: Group related habits into powerful routines.
- **Smart Reminders**: Set multiple alerts per routine (e.g., 15 min before AND 1 hour before).
- **Home Screen Widget**: Interactive widget to view and complete tasks directly from the home screen.
- **Offline First**: All data is stored locally on-device using SwiftData. No accounts, no tracking.
- **Insights**: Visual dashboards for streaks, consistency, and completion history.

## 🛠 Tech Stack

- **UI**: SwiftUI
- **Data**: SwiftData (Local Persistence)
- **Widgets**: WidgetKit
- **Background**: BGTaskScheduler (Background Fetch)
- **Notifications**: UserNotifications (Local)

## 🚀 Getting Started

### Prerequisites
- Xcode 15+
- iOS 17+ Simulator or Device

### Installation

1. Clone the repository
   ```bash
   git clone https://github.com/yourusername/protocol.git
   ```
2. Open `Protocol.xcodeproj` in Xcode.
3. Trust the signing profile if necessary.

### Important Configuration
The app uses **Background Tasks** for notification scheduling. Ensure your target's `Info.plist` includes:

- **Background Modes**: "Background fetch" enabled.
- **Permitted Identifiers**: `com.protocol.notification.refresh`

## 🏗 Architecture

The app uses a modern **MVVM** architecture with **SwiftData** for the model layer.

- **Models**: `MoleculeTemplate`, `MoleculeInstance`, `AtomTemplate`, `AtomInstance`.
- **ViewModels**: `MoleculeViewModel` (managed via `MoleculeService`).
- **Views**: Composable SwiftUI views split into `Components`, `Screens`, and `Sheets`.

## 🔒 Privacy

Protocol is privacy-first.
- No analytics.
- No third-party trackers.
- All data stays on the user's device.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

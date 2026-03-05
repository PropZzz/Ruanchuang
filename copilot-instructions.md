# BattleMan - AI Coding Assistant Guidelines

## Project Overview

**BattleMan** (时序智配) is a Flutter productivity app that intelligently schedules tasks based on user energy levels and cognitive state. It bridges the gap between calendar management and energy awareness through Material 3 design.

- **Platform**: Flutter (cross-platform: iOS, Android, web, Linux, macOS, Windows)
- **Architecture**: Screen-based navigation with service abstraction layer
- **Core Model**: Task scheduling aligned with energy/flow states

## Architecture Patterns

### Service Layer (Dependency Abstraction)
- **Location**: [lib/services/](lib/services/)
- **Pattern**: Interface-based (`DataService` abstract class) + Mock implementation (`MockDataService`)
  - `DataService`: Defines all app data needs (abstract contract)
  - `MockDataService`: Singleton in-memory implementation with simulated network delays
- **Usage**: Screens call `MockDataService.instance` to fetch data
- **Key**: Services return `Future<T>` to simulate async operations; always check `mounted` after awaits in StatefulWidgets to prevent setState on unmounted widgets

### Data Models
- **Location**: [lib/models/models.dart](lib/models/models.dart)
- **Core models**: `ScheduleEntry`, `EnergyStatus`, `Task`, `MicroTask`, `TeamMember`, `UserProfile`
- **Pattern**: Immutable `const` constructors for most models; `MicroTask` is mutable (local state tracking)
- **Time representation**: Uses `TimeOfDay` for hours/minutes; height units represent duration (80.0 ≈ 60 minutes)

### State Management
- **Approach**: Plain `StatefulWidget` with `setState()` — no external state management libraries
- **Critical pattern in MainScreen**: Uses `IndexedStack` to preserve page state (scroll position, form input) when switching tabs
- **Page loading**: Each page independently calls its data service in `initState()` and checks `mounted` after async operations
- **Important cleanup**: Always cancel timers/streams in `dispose()` to prevent memory leaks

## Navigation & UI Structure

### Tab Navigation
- **File**: [lib/screens/main_screen.dart](lib/screens/main_screen.dart)
- **5 tabs**: Focus → Calendar → MicroTasks → Team → Profile
- **State preservation**: `IndexedStack` with `NavigationBar` (Material 3)
- **Adding new tabs**: Update `_pages` list and `NavigationDestination` entries together

### Key Pages & Responsibilities

| Page | Purpose | Key Logic |
|------|---------|-----------|
| **FocusPage** | Current task + countdown + next tasks preview | Calculates current/upcoming based on `TimeOfDay` comparison |
| **SmartCalendarPage** | Time-blocking calendar view (8 AM-8 PM) | `_calculateTopOffset()` converts time → pixel position |
| **MicroTaskPage** | 5-15 min "crystal pool" fragment management | Local state; "快速添加" button triggers quick fill |
| **TeamPage** | Collaborator energy/progress display | Streams team member updates |
| **ProfilePage** | User settings & onboarding | (Minimal current implementation) |

## Design System

**Material 3 Theme** (Seed color based):
- **Primary Green** (#00BFA5): Flow state / high efficiency
- **Secondary Blue** (#2979FF): Collaboration / stable periods
- **Tertiary Orange** (#FF9100): Fatigue / fragmentation alerts

**Color coding in data**:
- Tasks use semantic colors mapped in `ScheduleEntry.color`
- Icons selected dynamically via [lib/utils/helpers.dart](lib/utils/helpers.dart) `iconForTag()` based on keyword matching

## Development Workflows

### Running the App
```bash
# Get dependencies
flutter pub get

# Run on device/emulator
flutter run

# Run with hot reload during development
flutter run --verbose
```

### Mock Data Flow
- `MockDataService` simulates network delays (50-120ms per call)
- Data mutations in one screen (e.g., adding schedule entry) currently don't sync across tabs
  - Future: integrate shared state management or service callbacks
- To modify mock data: edit `_scheduleData` list or override methods in `MockDataService`

### Common Patterns for New Features

**Adding a new data type**:
1. Define model in [lib/models/models.dart](lib/models/models.dart)
2. Add abstract method to `DataService` interface
3. Implement mock in `MockDataService` with delay simulation
4. Use in page via `_dataService.getInstance()`

**Adding a new page**:
1. Create `NewPage extends StatefulWidget` in [lib/screens/](lib/screens/)
2. Load data in `initState()`, check `mounted` after async
3. Add to `_pages` list in `MainScreen`
4. Add `NavigationDestination` entry

## Critical Developer Notes

### State Management Gotchas
- **Timer cleanup**: Always cancel timers in `dispose()` (see FocusPage line 29)
- **mounted check**: Essential after `await` in `initState()` / async callbacks to prevent "setState on unmounted widget" errors
- **IndexedStack preservation**: Switching tabs does NOT rebuild pages, so state persists — useful for avoiding expensive rebuilds, but remember to reset data when needed

### Time Calculations
- Convert `TimeOfDay` to minutes: `hour * 60 + minute`
- Duration from height: `(height / 80.0) * 60.0` minutes
- Time offset in calendar: minute delta from start hour × (hourHeight / 60)

### Async Data Loading Pattern
```dart
Future<void> _loadData() async {
  setState(() { _isLoading = true; });
  final data = await _dataService.getData();
  if (!mounted) return;  // ← Critical safety check
  setState(() {
    _data = data;
    _isLoading = false;
  });
}
```

## Testing & Debugging

- **No test framework currently integrated** — consider adding `flutter_test` if expanding features
- **Hot reload limitations**: Const values and global state won't reload; use hot restart instead
- **Dart Analysis**: Run `flutter analyze` to check code quality

## Dependency Summary

- `flutter` (Material 3 design)
- `flutter_lints` (code style)
- **No external state management libraries** (Riverpod, Provider, GetX, etc.)
- **No persistence layer** — all data in-memory mock only

---

**Last Updated**: 2026-01-26 | **App Version**: 0.1.0

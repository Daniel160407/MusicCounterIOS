# Music Counter for iOS

## Keep the iOS app and the extension in step

This app has a browser-extension companion at `../MusicCounter` (github.com/Daniel160407/MusicCounter).
They are one product: **any user-facing feature, setting, or behavior change made here must also be
made in the extension in the same task, and vice versa.** Do not finish a task with only one side done.

- Adapt the feature to each platform's idiom (SwiftUI screen ↔ popup tab, tab badge or notification ↔
  toolbar badge) rather than copying the UI literally, but keep the same behavior, thresholds and wording.
- Shared definitions must match exactly — same ids, goals, keys and order:
  - Achievements: `MusicCounter/Achievements.swift` ↔ `achievements.js`
  - Sync format (Firestore layout, part names, field names): `MusicCounter/Sync.swift`,
    `MusicCounter/SyncFormat.swift` ↔ `sync.js`
  - Settings shared through sync (e.g. history retention values): `MusicCounter/Models.swift` ↔ `background.js`
- Update both READMEs when behavior changes.
- Verify both sides: build the app
  (`xcodebuild -project MusicCounter.xcodeproj -scheme MusicCounter -destination 'generic/platform=iOS Simulator' build`;
  run `xcodegen generate` first if Swift files were added or removed), and syntax-check the extension's JS (`node`).
- If a change truly only applies to one platform (e.g. MPMediaLibrary reading, YouTube page detection),
  say so explicitly in your summary instead of silently skipping the other side.

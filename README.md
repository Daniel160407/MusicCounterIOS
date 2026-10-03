# Music Counter for iOS

Counts how much you listen to music in the iPhone **Music app**, including your own downloaded
MP3s, with no Apple Music subscription and no network. Works from the on-device media library
only (`MediaPlayer` framework, no MusicKit).

## Build (free Apple ID is enough)

1. Install **Xcode** from the Mac App Store and open it once to finish setup.
2. Create the project, either:
   - **XcodeGen:** `brew install xcodegen && xcodegen` in this folder, then open `MusicCounter.xcodeproj`; or
   - **Manually:** Xcode → File → New → Project → iOS App (SwiftUI, name `MusicCounter`), delete
     the template Swift files, drag in everything from `MusicCounter/`, and add the key
     **Privacy - Media Library Usage Description** (`NSAppleMusicUsageDescription`) in the
     target's Info tab.
3. Target → Signing & Capabilities → pick your Apple ID as the Team.
4. Plug in your iPhone, enable Developer Mode (Settings → Privacy & Security), pick the phone
   and press Run. Trust the developer in Settings → General → VPN & Device Management.

Free-account builds expire after 7 days; run again from Xcode to refresh. Data is kept as long
as you reinstall over the existing app.

## How it counts

- **Live** (app open or recently backgrounded): watches the system Music player and accrues real
  seconds; a song earns a play after half of it (a flat minute if the length is unknown).
- **Reconcile** (on every launch / return to foreground): compares each song's library
  `playCount` with the last snapshot and credits plays that happened while the app was closed,
  with time estimated as plays × duration. Plays already counted live are not counted twice.
- The first launch only records a baseline, so your existing play history isn't credited.
- Cloud-only (streamed, not downloaded) songs are skipped.

Stats are stored in `Documents/stats.json` on the device.

## Limits

- iOS suspends the app in the background, so exact minutes are only measured while it runs;
  otherwise they are estimated from play counts.
- Only songs in the Music app library are visible. MP3s played from the Files app or other
  player apps are not.

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

## Sync with the browser extension

Signed in with Google, the app shares its numbers with the
[Music Counter extension](https://github.com/Daniel160407/MusicCounter) through Firebase. Every
screen then shows this phone and the browser combined, favorites and the history-retention
setting are shared, and tapping a browser track opens it on YouTube, YouTube Music or Spotify.
Each device uploads only its own listening, and **Reset** erases only this phone's share.

Sync is off until it is set up (use the same Firebase project as the extension; see its README
for creating the project, Firestore and the Google provider):

1. Firebase console → **Project settings → Your apps → Add app → iOS**, bundle ID
   `com.daniel160407.MusicCounter`. Download **GoogleService-Info.plist** into `MusicCounter/`.
2. In `project.yml`, set `GOOGLE_REVERSED_CLIENT_ID` to the `REVERSED_CLIENT_ID` value from
   that plist. Google sign-in crashes without this URL scheme.
3. Run `xcodegen` again. It adds the Firebase and GoogleSignIn Swift packages, which Xcode
   downloads on the first build.
4. In the app: **⋯ → Sign in with Google**.

Uploads happen at most once a minute while music plays, and again when the app goes to the
background. Changes from the browser arrive live while the app is open.

## How it counts

- **Live** (app open or recently backgrounded): watches the system Music player and accrues real
  seconds; a song earns a play after half of it (a flat minute if the length is unknown).
- **Reconcile** (on every launch / return to foreground): compares each song's library
  `playCount` with the last snapshot and credits plays that happened while the app was closed,
  with time estimated as plays × duration. Plays already counted live are not counted twice.
- The first launch only records a baseline, so your existing play history isn't credited.
- Cloud-only (streamed, not downloaded) songs are skipped.

## Achievements

The **Insights** tab opens with an achievements card linking to the full list of 44 badges
(listening time, sessions, streaks, plays, variety, favorites, milestones). They count listening from every
synced device, a banner slides in when one is earned with the app open (plus a local
notification — a full alert if the app isn't on screen), and earned badges stay
earned after **Reset stats**. The definitions in `Achievements.swift` mirror the extension's
`achievements.js` — keep the two in step.

With Background App Refresh on, iOS also wakes the app now and then while it's closed (at
most hourly, usually less): it credits library plays, pulls the other devices' listening and
notifies you of any badge that earned. iOS picks the timing and skips it in Low Power Mode.

Stats are stored in `Documents/stats.json` on the device (and in Firestore once you sign in to sync).

## Limits

- iOS suspends the app in the background, so exact minutes are only measured while it runs;
  otherwise they are estimated from play counts.
- Only songs in the Music app library are visible. MP3s played from the Files app or other
  player apps are not.

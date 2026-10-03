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
While the other devices' stats are first fetched from Firestore (after signing in, or on launch),
the Today, Tracks, Insights and History screens show a pulsing loading skeleton.

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

**Browser remote:** while a song is loaded in YouTube, YouTube Music or Spotify in the
signed-in browser, the mini player shows it (with a computer icon and the service name) and
its **previous**, **play/pause** and **next** buttons press the browser player's own controls.
Presses take effect within a few seconds. The browser song's position isn't shared, so its bar
has no progress line. Your phone's own song takes the mini player while it
plays. The browser's song is hidden 3 minutes after the browser stops reporting it (it reports
once a minute while playing), or after 30 minutes paused. Tap the bar (or swipe it up) for
the full player: large cover, favorite star, the same three buttons, the song's combined time
and plays, which browser it's playing in, and a **volume** slider that sets the browser player's
volume when you let go of it (it takes effect within a few seconds; volume 0 counts as muted, so
that listening isn't counted). For YouTube and YouTube Music it runs from 0% to 200%, with the
browser's normal 100% in the middle and snapping to it nearby; above 100% the extension boosts the
sound (the slider turns orange), which only works in a tab you've clicked in. Spotify goes up to
100% only, and the player says so under the slider. Seeking, shuffle, repeat and AirPlay only work for the phone's own songs.

**Play on computer:** long-press a song in Library, Tracks, Today or History and pick
**Play on Chrome on …** to have the browser open it and start it: the track itself for a
browser song, or the first YouTube search result for a song from your library. Whatever the
browser was playing is paused. The browser checks for this every 30 seconds while it isn't
playing anything (every few seconds while it is), so it can take up to half a minute. Chrome
has to be running, and it may refuse to start sound in a tab you haven't clicked in yet. Only
browsers seen in the last 30 days are offered. The browser can't control the phone, because iOS suspends the app in the
background.

## How it counts

- **Live** (app open or recently backgrounded): watches the system Music player and accrues real
  seconds; a song earns a play after half of it (a flat minute if the length is unknown).
- **Reconcile** (on every launch / return to foreground): compares each song's library
  `playCount` with the last snapshot and credits plays that happened while the app was closed,
  with time estimated as plays × duration. Plays already counted live are not counted twice.
- The first launch only records a baseline, so your existing play history isn't credited.
- Cloud-only (streamed, not downloaded) songs are skipped.

## Library and playlists

The **Library** tab browses downloaded songs and playlists and plays them. **Recents**
lists the 100 most recently downloaded or added songs, newest first, grouped into Today, Yesterday,
This Week, This Month and Earlier, with Play and Shuffle for the whole list. To add music
to a playlist, swipe a song left or long-press it and pick **Add to Playlist**, or use the
toolbar button on a playlist to add all of its songs. Inside a playlist, **Add Songs** lists
your whole library with checkboxes: tick the songs that should be in it (ones already there
stay ticked) and tap **Add**. iOS gives apps no way to remove songs from a playlist, so that is
done in the Music app. Songs already in the playlist
are skipped. You can also make a new playlist from the same sheet. iOS only lets the app change
playlists it created, so for playlists made in the Music app it says so; add those songs in the
Music app instead.

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
- Playlists made in the Music app can be played but not edited here (an iOS restriction).
- Only songs in the Music app library are visible. MP3s played from the Files app or other
  player apps are not.

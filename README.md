# Sift

A native macOS app implementing **Smart Control** and **Auto-Sort**, built from
`Smart Control & Auto-Sort — Third-Party Apple Music Client PRD`, now connected
to a real Apple Music library via `MusicKit`.

Sift is framed as a standalone companion app that connects to a listener's
Apple Music library ("works with Apple Music," not a recreation of Apple's
own Music app) — per the PRD's note that the original mockup was drawn with
Apple's window chrome only to nail down interaction design quickly, and
needs its own visual identity before build. This app uses its own name, icon
tile, color system (teal → indigo → magenta accent, not Apple Music's red),
and window chrome.

## What's implemented

- **Real Apple Music connection** (`Sources/Sift/Music/`): `MusicAuthorizationService`
  requests library access, `MusicLibraryService` fetches your actual library
  playlists and their real songs/genres/artists via `MusicLibraryRequest`, and
  `PlaybackService` plays them for real through `ApplicationMusicPlayer`.
- **Playlist screen** with a connect flow: a "Connect Apple Music" prompt, then
  a picker over your real library playlists, then the playlist screen with
  Play / Shuffle / Smart Control / Auto-Sort — the latter two only shown on
  playlists with 25+ songs, per the PRD's discoverability-vs-clutter guidance.
  A "Use demo data instead" escape hatch is always available (uses the old
  mock playlist, clearly labeled, and doesn't touch MusicKit).
- **Smart Control**: the Familiarity dial, five weighted signals, and genre/
  artist filters from the earlier build, now actually driving playback order.
  `SmartControlEngine` scores each real song using **Sift's own listening
  history** (`ListeningHistoryStore`, a small JSON file in Application
  Support) — skips, replays, and minutes listened *through this app* — per
  the PRD's explicit note that Apple doesn't hand a third-party app your past
  Apple Music history; this has to build up from here going forward.
- **Auto-Sort**: Genre and Artist groupings are computed for real from the
  loaded playlist's actual songs (`AutoSortEngine`), and Create Playlists
  calls `MusicLibrary.shared.createPlaylist` to make real playlists in your
  library. Vibe stays empty/labeled Beta in connected mode — it needs a mood/
  energy classifier MusicKit's public API doesn't expose, which the PRD
  explicitly defers past v1 (demo mode still shows illustrative Vibe cards).

## Required: a paid Apple Developer Program membership

MusicKit's Media Library capability — needed to read your real playlists —
**is not available on a free Apple ID**, even for running the app locally on
your own Mac. It requires the **Apple Developer Program, $99/year**
(confirmed at [developer.apple.com/programs/enroll](https://developer.apple.com/programs/enroll/)).
There's no way around this for real library access; "Use demo data instead"
is there so the UI is still usable without it.

## Setting up the Xcode project

There's no `.xcodeproj` checked in. This environment has no macOS/Xcode/Swift
toolchain, so none of this has been built, run, or screenshotted — please
build-check it on your Mac before relying on it. To wire it up:

1. **Xcode → File → New → Project → macOS → App.** Interface: SwiftUI.
   Language: Swift. Name it `Sift`.
2. Delete the template's generated `ContentView.swift` and `SiftApp.swift`,
   then drag the entire `Sources/Sift/` folder from this repo into the
   project (check "Copy items if needed" and add to the Sift target). Keep
   the group structure (`App/`, `Models/`, `Music/`, `Support/`,
   `Components/`, `Views/`).
3. **Signing & Capabilities tab:** set your **Team** to your paid Apple
   Developer account, then **+ Capability → MusicKit**.
4. **Info tab (or Info.plist):** add key `Privacy - Media Library Usage
   Description` (`NSAppleMusicUsageDescription`) with a string like "Sift
   reads your Apple Music playlists to power Smart Control and Auto-Sort."
   — this is what makes the permission prompt show your own copy instead of
   crashing.
5. Build target macOS 13+ (Ventura), then Run. First launch shows the
   connect screen; approving the system prompt lets you pick a real library
   playlist.

The old `Package.swift` is kept only so `swift build` can type-check the
non-UI-framework parts quickly — it does **not** carry the MusicKit
entitlement, so running it via `swift run` will not get real library access.
The Xcode project above is the real, supported way to run this.

## Where I'm least confident

I can't compile or run this myself in this environment (Linux, no Xcode/
Swift toolchain, no Apple ID). Two spots in `Sources/Sift/Music/` are my best
recollection of MusicKit's API surface and are the most likely to need a
one-line fix from Xcode's autocomplete if the SDK you're on differs slightly:

- `MusicLibraryService.createPlaylist(name:songLibraryIDs:)` — the
  `MusicLibrary.shared.createPlaylist(name:items:)` call. `MusicLibrary`'s
  write API has shifted across SDK versions; if the signature doesn't match,
  autocomplete on `MusicLibrary.shared.` will show the current one.
- `PlaybackService.currentLibraryID()` — reads `player.queue.currentEntry?.item`
  and casts it to `Song` to know what's currently playing for history
  tracking. If `currentEntry`/`item` aren't named exactly this in your SDK,
  Xcode's autocomplete on `ApplicationMusicPlayer.shared.queue.` will show
  the right property.

Everything else (authorization flow, `MusicLibraryRequest`, `Playlist.with(.tracks)`,
`Song` metadata fields, `ApplicationMusicPlayer` playback) I'm confident in.

Minimum deployment target is macOS 13 (Ventura).

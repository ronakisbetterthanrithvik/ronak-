# Sift

A native macOS prototype of **Smart Control** and **Auto-Sort**, built from
`Smart Control & Auto-Sort — Third-Party Apple Music Client PRD`.

Sift is framed as a standalone companion app that connects to a listener's
Apple Music library ("works with Apple Music," not a recreation of Apple's
own Music app) — per the PRD's note that the original mockup was drawn with
Apple's window chrome only to nail down interaction design quickly, and
needs its own visual identity before build. This app uses its own name, icon
tile, color system (teal → indigo → magenta accent, not Apple Music's red),
and window chrome.

## What's implemented (PRD Phase 0 — Prototype)

- **Playlist screen** with Play / Shuffle, plus Smart Control and Auto-Sort
  entry points as pill buttons beside them — only shown on playlists with
  25+ songs, per the PRD's discoverability-vs-clutter guidance.
- **Smart Control**: the Familiarity dial (Rarely Played ↔ Balanced ↔ Most
  Played) with live caption text, the five weighted signals (Skips in
  Shuffle, Recently Played, On Repeat, Minutes Listened, Genre Balance) each
  with a Low/Med/High picker, genre and artist multi-select filters scoped
  to the playlist's own metadata, and Reset to Default / Cancel / Apply.
  Moving the dial pushes sensible defaults onto the three history-driven
  signals, matching the PRD's "dial is a simplified front end over the
  signal weights" behavior; per-playlist settings persist for the session.
- **Auto-Sort**: Genre / Vibe / Artist tabs (Vibe tagged **BETA**, since the
  PRD scopes Vibe mode to a later phase pending its own mood classifier),
  a card grid with checkboxes defaulting to selected, and a live
  "X of Y selected" counter feeding Create Playlists.
- Both panels render as translucent glass sheets (`NSVisualEffectView`)
  over the dimmed playlist, per the PRD's carried-through design principle.

## What's intentionally mocked or deferred

This build stops at Phase 0: it has **no real Apple Music / MusicKit
authentication, library sync, or MediaPlayer signal tracking** — the
playlist, songs, genres, artists, and Auto-Sort proposals are all local
mock data (`Sources/Sift/Models/MockData.swift`). "Create Playlists" and
"Apply" update in-memory state and show a confirmation toast rather than
writing back to a real library. iCloud/CloudKit sync, monetization, and the
Vibe classifier are out of scope here, per the PRD's own rollout gates.

## Running it

This is a Swift Package with a SwiftUI `App` entry point — there is no
Xcode `.xcodeproj` checked in (and this environment has no macOS/Xcode
toolchain to build or screenshot it), so it hasn't been compiled yet. On a
Mac with Xcode 15+ / Swift 5.9+:

```
open Package.swift        # opens the package directly in Xcode; press Run
```

or from Terminal:

```
swift run
```

Minimum deployment target is macOS 13 (Ventura).

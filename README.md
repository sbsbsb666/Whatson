# What’s On — London

A native SwiftUI Mac app: Today overview, Exhibitions, Gigs, Mixcloud and Cinema.

## Install & build (once)

1. Install Apple's command line tools (free, ~1 GB). In Terminal:
   ```
   xcode-select --install
   ```
   Full Xcode also works but isn't needed.
2. Get the code from its git repository and build:
   ```
   git clone https://github.com/sbsbsb666/Whatson.git ~/WhatsOn
   cd ~/WhatsOn
   bash build.sh --install
   ```
   This compiles the app, puts **What’s On** in /Applications and opens it.
   From then on, launch it from the Dock or Applications like any app.

The first build takes a minute or two. Building from a git clone (rather than the zip) is what turns on in-app updates.

## Updates

New versions install from inside the app — no reinstalling:

- The app checks the repository every few hours. When there's something new, an **Update available** card appears at the bottom of the sidebar.
- Or choose **What’s On → Check for Updates…**
- **Install and Relaunch** pulls the new code, rebuilds it on your Mac (a minute or two), swaps the app and reopens it. Your settings and cache are kept.

Because the update is compiled on your Mac, macOS treats it as your own app — no security prompts.
The repository address is set automatically from the clone; it's also in **Settings → Updates**.
If the repository is private, git on your Mac must be signed in to GitHub; a public repository needs nothing.

Requires macOS 14 (Sonoma) or later on Apple Silicon.

## First run

Open **What’s On → Settings… (⌘,)**:

- **Accounts** — your Songkick and Mixcloud usernames. If gigs don't load from the username, paste your Songkick calendar subscription link instead.
- **Galleries → West End Galleries** — every private gallery on GalleriesNow's West End page as a checklist, grouped by area. About 28 around Grafton Street are ticked to start (Zwirner, Hauser & Wirth, Pace, Ropac, Sprüth Magers, Max Hetzler, Thomas Dane, Pilar Corrias…). **Select** has quick presets.
- **Galleries → Museums & Other Galleries** — ArtRabbit pages and museum sites. **+** opens an Add Gallery sheet; double-click a row to edit, right-click to remove.
- **Cinemas** — Everyman Crystal Palace, BFI Southbank and Barbican are ticked. After the first refresh you can tick any of ~480 London venues.

⌘R refreshes everything. Results are cached, so the app opens instantly and works offline.

## Where the data comes from — and what might break

| Section | Source | Reliability |
|---|---|---|
| Cinema | Clusterflick's open data file (all London cinemas, rebuilt several times a day) | **Good.** No scraping on our side. BFI can't be scraped directly (Cloudflare), so this is the best route. The file has no formal schema promise. |
| Mixcloud | Mixcloud's official public API | **Best.** Can be rate-limited if you follow hundreds of accounts — failures show as a note, not an error. |
| Gigs | Songkick iCal calendar | **Fairly good.** iCal is a stable format, but Songkick was bought by Suno in late 2025 and the export could change. Any other `.ics` gig calendar can be pasted in instead. |
| Exhibitions (ArtRabbit) | ArtRabbit organisation pages | **Medium.** One layout for all galleries, so one fix repairs them all. |
| Exhibitions (Mayfair) | GalleriesNow West End listing — one page, ~60 galleries | **Medium.** A single request; one fix repairs every gallery. |
| Exhibitions (Tate) | Tate's own site, generic scraper | **Most fragile.** Any redesign may break it. |

Every section fails on its own: you'll see *Couldn't load — showing results from 3 hours ago* with a Retry button, and the other sections carry on. Within Exhibitions, a single gallery failing just adds a note.

## Fixing one source

Each source is one file under `Sources/WhatsOn/DataSources/`. The top comment of each file says what to check if it breaks.

```
DataSources/
  Cinema/ClusterflickSource.swift
  Gigs/SongkickSource.swift
  Gigs/ICalParser.swift
  Mixcloud/MixcloudSource.swift
  Exhibitions/ExhibitionsSource.swift      ← picks a scraper per gallery
  Exhibitions/ArtRabbitSource.swift
  Exhibitions/GalleriesNowSource.swift
  Exhibitions/GenericGallerySource.swift
```

Edit the file and push it to the repository — the app will offer the update. (Or run `bash build.sh --install` locally.)

To add a gallery that isn't on ArtRabbit: give the page address of its exhibitions list, and in *Link prefix* the path that each exhibition's link starts with (e.g. `/exhibitions/`).

## Project layout

```
App/        app entry point, AppModel (refresh + caching)
Core/       models, networking + HTML/date helpers, cache, settings, Updater
DataSources/  one module per source (above)
Views/      sidebar, Today, the four sections, cards, Settings
```

## Windows later

SwiftUI is Mac-only, so a Windows version means a new UI layer. The data sources are plain Swift, which does run on Windows, but the realistic path is to port the five source files to whatever the Windows app is written in — they are small and self-contained.

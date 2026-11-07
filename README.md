### ⚠️**Disclaimer**⚠️

**Lumen was developed entirely with Claude.**

As a result, bugs, unexpected behaviour and other issues may occur. Features may not always work as intended.

Use at your own discretion.
-- --

A Stremio-addon client for **iOS 12 and later** (iPhone 5s / iPad mini 2 / iPad Air and up), written in Swift + UIKit.

It speaks the same addon protocol as Stremio and Nuvio, so any addon manifest URL you use there works here.

## Features

- **Home**: catalog rows from every installed addon, plus *Continue Watching*
- **Discover**: browse any catalog by type, genre and year, with endless scrolling
- **Search** across all addons that support it
- **Details**: backdrop, info, seasons and episodes, resume
- **Streams**: filter by quality (4K/1080p/720p/SD), sort by quality, size or addon, and *Play Best*
- **Player**: VLC engine (plays MKV and almost every codec) or the iOS player; audio and subtitle tracks, addon subtitles (auto-selected in your language, adjustable timing), speed, fill/fit, resume
- **Auto-play next episode** with an *Up Next* countdown that sticks to the same source
- **Downloads** for offline viewing (also visible in the Files app)
- **Accounts**: import from **Stremio**; **Trakt** scrobbling and Continue Watching; **Nuvio** sign-in with addon, library and progress sync (self-hosted Nuvio servers)
- **Settings**: default player (built-in or VLC/Infuse/nPlayer/Outplayer), preferred quality, subtitle language, size and background
- Ships with **Cinemeta** (catalogs and details) and **OpenSubtitles** (subtitles). No stream sources are bundled; add the stream addons you want.

## Limits

- **Torrents** (`infoHash`-only streams) aren't playable — there's no torrent engine. Use addons that return HTTP(S) links.
- **Trakt** needs your own free Trakt API app (Client ID and Secret), entered in Settings → Accounts.
- **Nuvio**: the official Nuvio servers don't publish the details third-party apps need, so sign-in works with self-hosted Nuvio servers.

## Getting the IPA

Every push to `main` builds the app with GitHub Actions. Open **Actions → Build IPA**, pick the latest run, and download **Lumen-<version>-ipa** from *Artifacts*.

The IPA has no Apple signature, only an ad-hoc one. Install it with one of:

- **Jailbroken**: install AppSync Unified, then install the IPA with Filza. The IPA carries the entitlements AppSync installs need.
- **Sideload**: Sign the IPA via your preferred sideloading method. whether that be with your own Apple ID (re-sign every 7 days) or with your preferred signing service.

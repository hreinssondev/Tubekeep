# Tubekeep

A small macOS app that keeps a local library of YouTube videos. Save the video you're watching in
your browser with one shortcut, and Tubekeep starts playing it straight away while it downloads in
the background, then switches to the downloaded file without missing a beat.

Videos you haven't watched in a while are shrunk to a small copy to save space, and come back in
full quality the next time you play them.

## Features

- **Save from the browser**: press ⇧⌘S anywhere to save the YouTube video playing in Safari or
  Chrome (or the one in the front tab). Tubekeep picks it up from the same spot, or, if you prefer,
  just downloads it in the background while you keep watching in the browser.
- **Plays within seconds**: playback starts from YouTube's stream while a quick 480p copy and then
  the full-quality file download; each swaps in at the same position.
- **Your choice of quality**: 1080p by default; any video can be re-downloaded in 240p up to 2160p
  from the buttons next to the library (above 1080p needs a Mac that decodes AV1 in hardware).
- **Saves space by itself**: videos left unplayed for a few days are replaced with a small HEVC
  copy (480p by default). Playing one downloads full quality again. Pinned videos are never shrunk.
- **Keeps what YouTube loses**: if a video is removed from YouTube, the copy on your Mac is kept
  and marked as the only one left.
- **Library**: browse by date or in your own folders, Finder-style columns, drag and drop.
- **Other ways to add**: drop a link on the window, ⇧⌘V to add the link on the clipboard, or the
  `tubekeep://add?url=<link>` and `tubekeep://grab` URLs for Shortcuts, Raycast and bookmarklets.
- **Menu bar icon** with download progress, and open at login.

## Install

1. Download `Tubekeep-<version>.dmg` from the [latest release](https://github.com/hreinssondev/Tubekeep/releases/latest)
   and drag Tubekeep to Applications.
2. The app isn't notarized by Apple, so the first time macOS will refuse to open it. Right-click
   Tubekeep in Applications and choose **Open**, or go to **System Settings › Privacy & Security**
   and click **Open Anyway**.
3. On first launch Tubekeep downloads the tools it needs (yt-dlp, deno, ffmpeg and ffprobe, about
   330 MB on disk) into `~/Library/Application Support/TubeKeep/bin`, and keeps yt-dlp up to date.
4. The first time you use the shortcut, allow Tubekeep to control your browser when macOS asks
   (it reads the tabs to find the video).

Requires macOS 13 Ventura or later, on Apple silicon or Intel.

## Build from source

You need Xcode 16 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
git clone https://github.com/hreinssondev/Tubekeep.git
cd Tubekeep
xcodegen generate   # only needed after changing project.yml
open Tubekeep.xcodeproj
```

Set your own team in **Signing & Capabilities** (or change `DEVELOPMENT_TEAM` in `project.yml`),
then build and run. `scripts/make-dmg.sh` builds a universal, ad-hoc signed DMG into `dist/`.

## How it works

Tubekeep is a SwiftUI app that drives [yt-dlp](https://github.com/yt-dlp/yt-dlp) for downloads,
with [deno](https://deno.com) for YouTube's JavaScript challenges and [ffmpeg](https://ffmpeg.org)
for merging and the hardware HEVC transcodes. Files live in
`~/Library/Application Support/TubeKeep/Media`, one folder per video.

## Credits

- [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) by Jonas van den Berg,
  BSD 3-Clause (see `Vendor/LICENSE-mediaremote-adapter`), to pause the browser's playback.
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) by Sindre Sorhus, MIT.
- yt-dlp, deno and ffmpeg are downloaded at first launch and are not part of this repository.

Respect YouTube's Terms of Service and the rights of the people who make the videos; Tubekeep is
meant for keeping your own offline copies.

## License

[MIT](LICENSE)

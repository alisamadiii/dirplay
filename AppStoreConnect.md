# App Store Connect — Copy-Paste Sheet

Everything below maps to a field in App Store Connect. Copy each block as-is.

---

## Name (30 characters max)

```
Dirplay — Folder Music Player
```

## Subtitle (30 characters max)

```
No ads. No tracking. Just play
```

## Description

```
Dirplay is a music and video player with a radical idea: your folders are your library.

Pick any folder. Dirplay reads it and plays it. That's the whole app.

No ads. Ever.
No tracking. Ever. Dirplay collects nothing — no analytics, no accounts, no cloud. Your files never leave your device. There isn't even a database: the app literally reads your folder structure and mirrors it exactly, the way you organized it.

MUSIC
• Your folder structure is your library — never flattened, never "sorted for you"
• Beautiful now-playing screen with artwork, scrubbing, shuffle, and repeat
• Background playback with full lock screen and Control Center support
• Gentle fade in/out on play and pause
• Embed cover art directly into your MP3 and M4A files
• Playback speed from 0.5× to 2×

VIDEO
• Custom player with double-tap skip, hold for 2× speed, and scrub previews
• Pinch to fill the screen, swipe for brightness and volume in landscape
• AirPlay to your TV or Mac

Supports MP3, M4A, FLAC, WAV, AAC, AIFF, MP4, MOV and more.

Free. Open source. Yours.
```

## Keywords (100 characters max)

```
music player,video player,offline,local,folder,mp3,m4a,flac,no ads,file player,audio,files
```

## Support URL

```
https://github.com/alisamadiii/dirplay
```

## Marketing URL (optional — can leave empty)

```
https://github.com/alisamadiii/dirplay
```

## Privacy Policy URL (App Information → Privacy Policy)

```
https://alisamadiii.github.io/dirplay/
```

## Copyright

```
2026 Ali Samadi
```

## Version

```
1.0
```

---

## App Information

- **Primary Category:** Music
- **Secondary Category:** Utilities (optional)
- **Content Rights:** does not contain, show, or access third-party content
- **Age Rating questionnaire:** answer **No / None** to everything → results in **4+**

## App Privacy (Trust & Safety → App Privacy)

- "Do you or your third-party partners collect data from this app?" → **No**
- Result: **Data Not Collected** label. (Matches the bundled PrivacyInfo.xcprivacy.)

## Pricing and Availability

- Price: **Free** (USD 0)
- Availability: all countries (or your pick)

## App Review Information (General → App Review)

- Sign-in required: **No**
- Notes — paste this:

```
Dirplay plays the user's own local files and requires no account. To test: open the Files app, create a folder containing "Music" and "Video" subfolders, add any audio/video files to them, then launch Dirplay and select that folder from the welcome screen. The app mirrors the folder structure and plays the files. No data is collected; the only network request is a version check against Apple's public iTunes Lookup API.
```

## Build

1. Xcode → open Dirplay.xcodeproj → select "Any iOS Device (arm64)" as destination
2. Product → **Archive**
3. Organizer window → **Distribute App** → App Store Connect → Upload (defaults are fine)
4. Wait ~10–30 min for processing, then select the build in this version page
5. The export-compliance question is answered automatically (ITSAppUsesNonExemptEncryption = NO in Info.plist)

## Screenshots (required before "Add for Review" works)

- Required size: **6.9" iPhone — 1320 × 2868** (or 1290 × 2796)
- Minimum 1, up to 10. Plain simulator screenshots are acceptable to start; replace with designed ones later.
- Quick capture: run the app in the iPhone 17 simulator → Cmd+S saves a correctly sized PNG to Desktop.

## Notes

- The app icon in App Store Connect appears only after the first build is uploaded and processed — the placeholder before that is normal.
- App version releases: choose "Manually release this version" if you want control of the go-live moment after approval.

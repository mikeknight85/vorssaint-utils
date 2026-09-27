# AirPlay Now Playing mirror: investigation notes

Status: **prototype, not for review.** Parked here until the per-app AirPlay route
(PR #2082) is accepted. Whether this becomes a follow-up PR is open for discussion
with the maintainer.

## Goal

When an app is routed to AirPlay through Vorssaint, iPhones and iPads should show the
song, artist and artwork on the speaker's card (Home app, Control Center, lock screen),
and their controls, and the Mac's media keys, should keep working.

## Why nothing shows without this

The per-app stream is played by Vorssaint's own `AVSampleBufferAudioRenderer`. The
Mac's AirPlay sender attaches the Now Playing information of the process that owns
the stream, which is Vorssaint, and Vorssaint publishes none. The speaker shows only
its own name.

## Experiments

All on a HomePod mini, MacBook Pro M1 Pro, macOS 27.0, Spotify as the source app.

| # | Change | Result |
|---|---|---|
| E1 | `-[AVOutputContext setApplicationProcessID:]` = Spotify's pid | No effect. The pid is set (logged 0 → pid), but the speaker still shows only its name. |
| E2 | Context pid = Vorssaint, publish fixed test metadata via `MPNowPlayingInfoCenter` (+ play/pause handlers) | Test title and the Vorssaint icon appear on the iPhone. |
| E2b / P1 | No context pid; mirror Spotify's real info (new helper mode `app <pid>`, polled every 2 s) | Real title, artist and artwork appear. The private pid call is not needed. |
| – | Side effect of P1 | Vorssaint becomes the Mac's **global Now Playing app**. F8/F9 and all MediaRemote commands go to Vorssaint. |
| P2 | Forward iPhone commands to Spotify's player through MediaRemote | Since macOS 15.4, MediaRemote redirects commands from non-Apple callers to the global Now Playing app, which is Vorssaint: a feedback loop (about 1,240 commands in 2 minutes). Track-scoped commands fail with error 7. |
| E4 | `MRMediaRemoteSetCanBeNowPlayingApplication(false)` | No effect; Vorssaint is still chosen. |
| E5 | Publish info but report `playbackState = .paused` | Still chosen (Vorssaint really produces audio). The lock-screen card disappears and the time stops, so this was reverted. |
| P3 | Loop guards; pause stops our renderer; resume restarts its timeline | Guards work. The AirPlay session paused by the system stays silent after resume (it recovered by itself only after a minute or more). |
| P4 | Forward commands with **Apple Events** to the source app (reusing `NotchMusicAutomationCapabilities`); report the real play state | Play, pause, next, previous from the iPhone and F8/F9 on the Mac all reach Spotify. The lock screen and running time come back. |
| P5 | Resume creates a **fresh renderer and synchronizer**; toggles are debounced by 0.5 s; stopping drains the feed queue | Pause and resume work from the Mac and the iPhone. **Tested working end to end.** |

## Resulting design (prototype)

- While at least one app streams to AirPlay, Vorssaint mirrors that app's Now Playing
  info (title, artist, album, duration, position, rate, artwork) into
  `MPNowPlayingInfoCenter`. It is read per app through `NowPlayingAdapter`'s new
  `app <pid>` mode, because MediaRemote cannot be read in process since macOS 15.4.
- Vorssaint is the Mac's Now Playing app during that time. That cannot be avoided, so it
  acts as a proxy:
  - pause stops our renderer and sends `pause` to the source app;
  - play drops buffered audio, recreates the renderer and sends `play`;
  - next, previous and seek go to the source app.
- Commands to the source app use Apple Events (Automation permission, prompted once per
  player; the entitlement and usage string already exist). MediaRemote cannot be used:
  it loops back.
- Loop guards: a forwarded command blocks another forward for 0.8 s; toggles within
  0.5 s are ignored.
- When the last AirPlay stream stops, the published info is cleared.

## Before this could become a PR

- Replace the 2 s polling with the adapter's watch mode (notifications, artwork
  de-duplicated).
- Apps without a scripting dictionary (browsers): only our own stream follows
  play/pause, and next/previous/seek are disabled on the remote.
- Handle a declined Automation permission gracefully.
- Check the notch: it reads the system Now Playing, which is Vorssaint while mirroring.
- Several apps on AirPlay at once: decide which one is mirrored.
- Remove the experiment logging (`~/Library/Logs/Vorssaint-airplay-experiment.log`),
  the E1 context-pid code and the unused `resumeIfStalled`.
- Tests for the command mapping, the loop guards and the adapter reply parsing;
  localization; discuss the Automation-permission use with the maintainer.

Untested so far: the position slider on the iPhone, Apple Music as the source,
non-scriptable sources, declining permission, two apps on AirPlay, and long sessions.

# Ideas

These aren't built yet. Each note says what it would take in this codebase, how much work it is, and what it adds. Effort is **S** (one file, no new permissions), **M** (several files or a new subsystem), or **L** (new audio paths, new permissions or a new distribution channel). Value is how much a typical Notch DJ user would notice it.

| Idea | Effort | Value |
|---|---|---|
| BPM per deck | M | Medium |
| Cue / pre-listen on headphones | L | High for DJs |
| Per-app EQ presets | S | Medium |
| MIDI controller mapping | M | High for DJs |
| Shortcuts and AppleScript | M | Medium |
| Record the master | M | Medium |
| Load Spotify or Music tracks onto a deck | L | Medium |
| Auto-crossfade | S | Medium |

## BPM per deck

Show a tempo readout on each deck, and later a "sync" hint between decks.

- **How:** the tap's IO block already sees every buffer. Add an onset detector there (spectral flux on a 1024-sample hop) that writes onset times into a lock-free ring, like `MeterBank`'s history. A low-priority task on the engine queue autocorrelates the last 8 seconds and publishes a BPM with a confidence value. No new permission is needed.
- **Effort: M.** The detector is about 200 lines. The hard part is staying stable on music without drums, so only show the readout above a confidence threshold.
- **Value: medium.** It's a real DJ cue, but the decks can't change tempo, so it can only inform the user.

## Cue / pre-listen on headphones

Hear the cued deck on a second output (headphones) while the master keeps playing to the speakers.

- **How:** today CUE is solo on the master. Real pre-listen needs a second aggregate device that pairs the deck's tap with the headphone output, and the tap would feed both outputs. `ProcessVolumeTap` already rebinds a tap to a chosen output. Pre-listen means rendering one tap into two IO procs, with separate gain on each.
- **Effort: L.** It needs two clocks with drift correction, a Settings choice for the cue output, and testing with AirPods (Bluetooth latency).
- **Value: high for people who actually DJ,** and invisible to everyone else.

## Per-app EQ presets

Save the deck tone (HI / MID / LOW / FILTER / GAIN) as a named preset, and apply it to an app whenever it plays: "Podcast" for Overcast, "Bass cut" for the browser.

- **How:** `DeckTone` is already a small `Sendable` struct, and volume memory already stores per-app state in `DJDefaults.suite`. Store a preset name per bundle ID and apply it in the same place saved levels are applied. Add a menu to each MIXER strip and DJ deck.
- **Effort: S.**
- **Value: medium.** It's most useful for speech apps and laptop speakers.

## MIDI controller mapping

Map a cheap USB controller (Korg nanoKONTROL, Akai MIDImix, DDJ-200) to faders, knobs, cue and the crossfader.

- **How:** use CoreMIDI with a `MIDIInputPortCreateWithProtocol` callback. Forward messages to the main actor, and from there to the same `AppVolumeMixer` setters the UI calls, so all audio work stays on the engine queue. Add a "learn" mode: click a control, move a hardware control, and save the mapping in the defaults suite.
- **Effort: M.** The learn UI and soft takeover (don't jump a value until the hardware control passes it) are most of the work.
- **Value: high for DJs.** It turns the notch into a real controller target.

## Shortcuts and AppleScript

Actions like "Set Spotify to 40 %", "Mute app", "Load app on deck A", "Set crossfader" and "Duck now".

- **How:** use App Intents (`AppIntent` with an `AppEntity` for running audio apps). They run in-process on macOS 14 and work with the Shortcuts app and Spotlight. Each intent calls `AppVolumeMixer` on the main actor. AppleScript would need an `.sdef` and Cocoa scripting, so start with App Intents.
- **Effort: M.** App Intents needs the app built with Xcode's metadata processor (`appintentsmetadataprocessor`). That means adding an Xcode project or a build step to `build.sh`.
- **Value: medium.** It's powerful for automation, such as Focus modes and calendar triggers.

## Record the master

Record what you hear (the master after Notch DJ's changes) to an M4A file.

- **How:** add a global tap (`CATapDescription(stereoGlobalTapButExcludeProcesses: [])`) on the engine queue that writes to `AVAudioFile` from the IO block through a ring buffer and a writer thread. Show a red dot in the top bar while recording. It uses the System Audio Recording permission Notch DJ already has.
- **Effort: M.** The writer thread and handling device changes mid-recording are the risky parts.
- **Value: medium.** It's a clear feature, but it has to be explained carefully, because today the privacy message promises that nothing is recorded. It should be opt-in, with a visible indicator.

## Load Spotify or Music tracks onto a deck

Browse a playlist on a deck and load a track, instead of loading an app.

- **How:** Music can be scripted (`play track` in a playlist). Spotify's AppleScript can play a URI but can't browse, so browsing would need the Spotify Web API with OAuth. Both decks still map to one app each, so "two tracks at once" only works with two different players (Music on A, Spotify on B).
- **Effort: L.** It needs OAuth, a network permission story, and the "one app, one deck" model to be explained.
- **Value: medium.** It's impressive in a demo, but limited by the players.

## Auto-crossfade

One button that moves the crossfader from A to B over 4, 8 or 16 seconds, with the selected curve.

- **How:** a small ramp object drives `AppVolumeMixer.setCrossfade(_:)` from a `Task` on the main actor at 30 Hz, so the audio work is still sent to the engine queue. With Reduce Motion it jumps instead. If the user grabs the crossfader during a ramp, the ramp stops.
- **Effort: S.**
- **Value: medium.** It's the most-asked "DJ" feature that fits the per-app model well.

## Smaller ones

- **Per-output presets:** remember levels per output device, for example quieter for headphones. (S)
- **Mute on screen lock:** mute chosen apps when the screen locks. (S)
- **Mini meter in the closed notch:** a live meter while closed. This goes against "quiet when closed", so make it opt-in. (S)
- **Haptic beat on the trackpad:** a light `.generic` haptic on each detected beat while dragging the crossfader. Depends on BPM. (S)

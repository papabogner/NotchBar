# Changelog

All notable changes to Notch DJ. Versions follow [Semantic Versioning](https://semver.org).

## 0.2.0

A new interface, built around a bigger panel and three views.

### Added

- **HOME**, the new first tab: now playing with big artwork, transport and a scrubber; the master volume as a knob with a stereo meter; the output device; and every app that's making sound, with a mini meter and mute.
- **Five DJ templates:**
  - Studio, in light or dark
  - K.O.
  - Hardware Black
  - Club, with spinning platters
  - Minimal

  Pick one from the panel's top bar or in Settings › Appearance. All of them share the same controls and audio engine.
- **Panel sizes:** Compact, Regular (the default) and Large. The panel fits itself to the screen.
- **Onboarding:** an intro, a tour of the three views, audio access with a live status, a template picker with a live preview, shortcuts and launch at login. You can run it again from Settings.
- **A Settings window** with General, Appearance, Audio, Extras and About tabs.
- **Volume memory:** each app's level, mute and output come back when it plays again.
- **Auto-ducking:** other apps get quieter during calls. You can include Meet in a browser and choose an extra call app.
- **Media keys:** the transport buttons can control players that can't be scripted. This is optional and needs Accessibility.
- **A menu bar icon** for Macs without a notch. You can also set it to always or never.
- **Controls:**
  - Meters with peak hold, and a level history per deck.
  - Haptic detents and double-click to reset.
  - Scroll wheel support, and ⌥ for fine steps.
  - A value bubble while you move a control, and VoiceOver adjust actions.
- **Motion:** spring open and close, a sliding tab indicator, and artwork that moves between HOME and DJ. All of it follows Reduce Motion.
- **German localization.**
- `scripts/setup-signing.sh`, which creates a stable local signing certificate so permissions survive rebuilds.
- `scripts/extract-strings.py`, which checks the string tables against the code.
- README sections on permissions, releasing with Developer ID and notarization, and an FAQ.
- `docs/DESIGN.md` and `docs/IDEAS.md`.

### Changed

- **Permissions:**
  - Notch DJ no longer asks for System Audio Recording at launch.
  - It checks quietly, and asks only from onboarding, Settings or the note that appears when you first change an app's volume.
  - After a denial, it points to System Settings instead of asking again.
- **Bigger controls:** faders are at least 160 pt tall and knobs at least 44 pt.
- **Closed notch:** it stays exactly the size of the hardware notch while idle, and shows small wings with artwork while music plays.
- **Faster meters:** meters only run while the panel is open, at 30 fps. Nothing polls while it's closed.
- **Signing order in `build.sh`:** Notch DJ Local Signing, then NotchBar Local Signing, then ad hoc with a warning.

### Removed

- The v0.1 MIXER and DJ views, and the menu-based settings.

## 0.1.0

- The first version, split from NotchBar:
  - Per-app volume with Core Audio process taps.
  - A flat mixer.
  - A two-deck DJ view with EQ, filter, gain, cue and a crossfader.
  - Now playing for Music and Spotify.
  - The ⌃⌥N and ⌃⌥M shortcuts.

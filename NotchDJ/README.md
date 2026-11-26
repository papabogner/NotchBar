# Notch DJ

A music-only notch: per-app volume, a flat mixer, and a two-deck DJ view. Nothing else.

Notch DJ is based on NotchBar by [srisanthosh/NotchBar](https://github.com/srisanthosh/NotchBar). It is licensed under the GNU General Public License version 3. See [LICENSE](LICENSE) and [NOTICE](NOTICE).

## Requirements

- macOS 14 or later
- macOS 14.4 or later for per-app volume (process taps). The app still opens on 14.0–14.3, but the faders cannot change other apps there.
- Xcode or a Swift 6 toolchain

## Build

```bash
cd NotchDJ
./build.sh
```

The app is written to `NotchDJ/build/Notch DJ.app`. `./build.sh --run` quits a running copy and opens the new one.

The script signs with the parent repo's "NotchBar Local Signing" certificate when that certificate is installed, and ad hoc otherwise. Ad hoc builds ask for System Audio Recording again after each rebuild.

## Permissions

macOS asks for **System Audio Recording** the first time a fader leaves 100%, an app is muted, or a deck tone is not flat. Notch DJ does not record or store audio.

Music and Spotify titles use AppleScript. macOS may ask for Automation access the first time one of those apps is playing.

## Features

- Closed notch with the current Music or Spotify title. Hover opens the mixer. Click the notch to toggle it.
- **MIXER | DJ** in the header. MIXER is the flat channel strips. DJ is two decks with EQ, filter, gain, cue, and meters.
- Crossfader curves: SMOOTH, DIP, CUT.
- System volume knob and output-device menu, including AirPlay devices macOS is exposing.
- Peak and RMS meters while the mixer is open. They stop when it closes.
- Shortcuts, on until you turn them off: ⌃⌥N toggles the notch, ⌃⌥M opens it or switches MIXER / DJ. If NotchBar is also running, it may already own those keys.
- Settings: output device, silent apps, crossfader curve, hotkeys, launch at login. Animations follow the system Reduce Motion setting.

Notch DJ keeps its own preferences (`com.local.notchdj`) and its own Application Support folder (`Notch DJ`). It does not read NotchBar's settings.

## Not included

Claude usage, agents, ticker, news, Mac mini, portfolio, Spotify Connect, activity, calendar, weather, camera, clipboard, file shelf, dictation, menu-bar cleanup, home cards, timer, and scenes.

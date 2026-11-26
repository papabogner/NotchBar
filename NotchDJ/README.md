# Notch DJ

Notch DJ puts per-app volume, a mixer and two DJ decks in your Mac's notch. Move the pointer to the notch, and the panel opens with the volume of every app that's making sound.

Notch DJ is based on [NotchBar by srisanthosh](https://github.com/srisanthosh/NotchBar). It is free software under the GNU General Public License, version 3. See [LICENSE](LICENSE) and [NOTICE](NOTICE).

<!-- Screenshot placeholders. Capture at the Regular panel size, dark appearance, with Spotify playing,
     and save them under docs/screenshots/ with these names. -->

| HOME | MIXER | DJ (Studio) |
|---|---|---|
| ![HOME: now playing, master volume and playing apps](docs/screenshots/home.png) | ![MIXER: one strip per app and the master strip](docs/screenshots/mixer.png) | ![DJ in the Studio template](docs/screenshots/dj-studio.png) |

| K.O. | Hardware Black | Club | Minimal |
|---|---|---|---|
| ![DJ in the K.O. template](docs/screenshots/dj-ko.png) | ![DJ in the Hardware Black template](docs/screenshots/dj-hardware.png) | ![DJ in the Club template](docs/screenshots/dj-club.png) | ![DJ in the Minimal template](docs/screenshots/dj-minimal.png) |

![Onboarding](docs/screenshots/onboarding.png)

## Features

- **HOME** shows:
  - What's playing, with big artwork, transport and a scrubber for Music and Spotify.
  - The master volume as a big knob with a stereo meter, and the output device.
  - Every app that's making sound, with a mini meter and mute. Click an app to jump to its MIXER strip.
- **MIXER** has a channel strip per app, with a fader up to 150 %, a meter, mute, solo and its own output device. The master strip is pinned on the right.
- **DJ** puts two apps on two decks, with HI / MID / LOW EQ (with kill), a filter, gain, CUE and a crossfader with SMOOTH, DIP and CUT curves.
- **Five looks for DJ:** Studio (light or dark, in your accent color), K.O., Hardware Black, Club (spinning platters) and Minimal. Switch from the panel's top bar or in Settings › Appearance. Every look has the same controls.
- **Three panel sizes:** Compact, Regular and Large. The panel also shrinks to fit smaller screens.
- **Controls:**
  - Drag knobs and faders, or use the scroll wheel. Hold ⌥ for fine steps.
  - Double-click a control to reset it. Values show while you move a control.
  - The trackpad clicks at 100 % and at the center.
- **Volume memory:** each app's level, mute and output come back when it plays again.
- **Auto-ducking:** other apps get quieter while you're on a call, for example in Zoom, FaceTime, Teams, Slack, Discord or Meet in a browser.
- **Media keys** (optional): the transport buttons also control players that can't be scripted, such as a browser tab.
- **Menu bar icon** for Macs without a notch, or always if you prefer.
- **Keyboard:** ⌃⌥N opens or closes the panel. ⌃⌥M opens MIXER, then switches between MIXER and DJ.
- **Onboarding** on first launch, which you can run again from Settings.
- **Languages:** English and German.
- **Quiet when closed:** nothing animates, polls or meters while the panel is closed.

## Requirements

- macOS 14 Sonoma or later. Per-app volume needs macOS 14.4 or later, because it uses Core Audio process taps. On 14.0–14.3, HOME, the master volume, the output switch and the media controls work, but the app faders can't change other apps.
- A Swift 6 toolchain: Xcode 16 or later, or the Xcode Command Line Tools for Xcode 16 or later (`xcode-select --install`).

## Build and run

```bash
git clone https://github.com/papabogner/NotchBar.git
cd NotchBar/NotchDJ
./scripts/setup-signing.sh   # once per Mac; see below
./build.sh --run
```

`build.sh` builds a release binary with SwiftPM and assembles `build/Notch DJ.app`. With `--run`, it also quits a running copy and opens the new build.

For launch at login, put the app in Applications:

```bash
ditto "build/Notch DJ.app" "/Applications/Notch DJ.app"
open "/Applications/Notch DJ.app"
```

### Why setup-signing.sh?

macOS ties permissions to an app's code signature. An ad hoc signed app counts as a new app after every build, so macOS would ask for System Audio Recording and Automation again each time.

`scripts/setup-signing.sh` creates a self-signed code-signing certificate called "Notch DJ Local Signing" in your login keychain. It only works for code signing and never leaves your Mac. `build.sh` uses the first of these that it finds:

1. Notch DJ Local Signing
2. NotchBar Local Signing (the parent project's certificate)
3. Ad hoc, with a warning

The script is safe to run again. If macOS asks for your login password to trust the certificate, that's expected.

## Permissions

Notch DJ never asks for a permission at launch. It checks quietly and only asks when you use something that needs it.

| Permission | Needed for | When macOS asks |
|---|---|---|
| **System Audio Recording** | Per-app volume, MIXER, DJ, meters and ducking | When you click "Allow Audio Access" in onboarding, in Settings › Audio, or in the note that appears the first time you change an app's volume |
| **Automation** (Music, Spotify) | Track info, artwork and transport for Music and Spotify | The first time one of them is playing |
| **Accessibility** (optional) | Media keys for other players | When you turn on media keys in Settings › Extras |

**What System Audio Recording means here:** to change one app's volume, Notch DJ taps that app's audio with Core Audio, processes it live, and plays it back. The audio is never recorded, stored or sent anywhere. macOS shows the purple recording indicator in the menu bar while a tap is active.

If you said no, turn Notch DJ on in System Settings › Privacy & Security › Screen & System Audio Recording. Notch DJ notices the change by itself.

To reset a permission and be asked again:

```bash
tccutil reset AudioCapture com.local.notchdj
tccutil reset AppleEvents com.local.notchdj
tccutil reset Accessibility com.local.notchdj
```

## Releasing a build for other Macs

Local builds are signed with your own certificate, so other Macs won't trust them. To share Notch DJ, sign it with a Developer ID certificate, enable the hardened runtime, and notarize it.

1. **Get a Developer ID Application certificate.** This needs an Apple Developer Program membership. Create the certificate in Xcode › Settings › Accounts › Manage Certificates. Check that it's installed:

   ```bash
   security find-identity -v -p codesigning | grep "Developer ID Application"
   ```

2. **Save your notarization credentials once.** Use an app-specific password from [account.apple.com](https://account.apple.com):

   ```bash
   xcrun notarytool store-credentials notchdj \
     --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-password"
   ```

3. **Build, sign, notarize and staple:**

   ```bash
   cd NotchDJ
   ./build.sh
   codesign --force --deep --options runtime --timestamp \
     --entitlements Resources/NotchDJ.entitlements \
     --identifier com.local.notchdj \
     --sign "Developer ID Application: Your Name (TEAMID)" "build/Notch DJ.app"
   codesign --verify --strict --verbose=2 "build/Notch DJ.app"
   ditto -c -k --keepParent "build/Notch DJ.app" "build/Notch DJ.zip"
   xcrun notarytool submit "build/Notch DJ.zip" --keychain-profile notchdj --wait
   xcrun stapler staple "build/Notch DJ.app"
   spctl --assess --type execute --verbose "build/Notch DJ.app"
   ```

4. **Ship it.** Zip the stapled app again, or put it in a DMG, and publish that.

Notes:

- The hardened runtime blocks Apple Events unless the app has the `com.apple.security.automation.apple-events` entitlement. Without it, Music and Spotify track info stops working. `Resources/NotchDJ.entitlements` includes it, plus `com.apple.security.device.audio-input`, which the hardened runtime may require for audio taps.
- Before you publish, change the bundle identifier from `com.local.notchdj` to one you own, such as `com.yourname.notchdj`. Change it in `Resources/Info.plist` and in the `--identifier` above. Permissions are stored per identifier, so users will be asked again once.
- Notch DJ isn't sandboxed. Process taps and AppleScript control of other apps don't work in the App Sandbox, so it can't ship on the Mac App Store as it is.

## FAQ

**macOS asks for System Audio Recording again after every build.**
The app is signed ad hoc. Run `./scripts/setup-signing.sh` once, then `./build.sh` again. You'll be asked one more time, and then the answer sticks.

**Does Notch DJ record my audio?**
No. Audio passes through a tap so its volume and tone can change, and then it goes straight to the output. Nothing is written to disk or sent over the network. macOS calls this permission "recording" because a tap could record.

**Why is there a purple dot in the menu bar?**
macOS shows it whenever an app has an audio tap open. Notch DJ only taps an app while it's changing that app: a level other than 100 %, a mute, a solo, a deck tone, the crossfader or ducking. It also taps while the panel is open, for the meters. Close the panel and reset an app to 100 %, and its tap goes away. You can turn off "Live meters while the panel is open" in Settings › Audio.

**An app doesn't show up in MIXER.**
Only apps that are making sound appear. Turn on "Show silent apps" under MIXER to see every app that has used audio.

**The play button doesn't control my browser.**
Music and Spotify are controlled directly. For other players, turn on media keys in Settings › Extras and allow Accessibility.

**My Mac doesn't have a notch.**
Notch DJ shows a menu bar icon instead (Settings › Extras › Menu bar icon: Without a notch). Click it to open the panel, and right-click it for the menu.

**⌃⌥N does nothing.**
Another app may own the shortcut. NotchBar uses the same keys, and the first app to start gets them. Shortcuts can be turned off in Settings › General.

**How do I start over?**
Quit Notch DJ, then run:

```bash
defaults delete com.local.notchdj
rm -rf "$HOME/Library/Application Support/Notch DJ"
```

The onboarding then runs again on the next launch. You can also open it any time from Settings › General › Show Onboarding….

**How do I uninstall it?**
Quit it, turn off Launch at Login, delete the app, and run the two commands above. To remove the signing certificate, delete "Notch DJ Local Signing" in Keychain Access.

## Development

- `Sources/NotchDJ/` is the app:
  - `Audio/` and `Mixer/` hold the tap engine, which runs on its own queue.
  - `Panel/` holds HOME, MIXER and the DJ layouts.
  - `Theme/` holds the templates.
  - `Onboarding/` and `Settings/` hold the windows.
- `docs/DESIGN.md` is the design spec, including how to add a DJ template.
- `docs/IDEAS.md` lists features that aren't built yet, with effort and value notes.
- `python3 scripts/extract-strings.py --check` checks that every UI string is in the English and German string tables.

## Credits and license

Notch DJ is based on [NotchBar](https://github.com/srisanthosh/NotchBar) by srisanthosh. The original copyright remains with the NotchBar authors. Notch DJ's changes are distributed under the same license, the [GNU General Public License, version 3](LICENSE).

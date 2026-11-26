# Notch DJ design

Short spec for v0.2. Code follows this document; change both together.

## Principles

- **Flat and native.** SF Pro and SF Mono, SF Symbols, system controls in windows. Vibrancy only where macOS uses it (Settings, Onboarding). No glass, no depth gradients, no 3D.
- **Teenage Engineering influence.** Monochrome with one accent, an 8 pt grid, small caps labels (10 pt, +0.6 tracking), mono numerals for every value.
- **Quiet when closed.** The closed notch is black and static. Nothing animates, polls or meters while it is closed.
- **Audio off the main thread.** The UI sends snapshots to the engine queue and reads atomics back. It never calls Core Audio tap APIs.

## Information architecture

```
Closed notch ──hover 0.25 s / click / ⌃⌥N──▶ Panel
Panel
 ├─ HOME    now playing · master · output · playing apps · jump to MIXER / DJ
 ├─ MIXER   one strip per app · master strip
 └─ DJ      two decks + crossfader, laid out by the template
 Top bar    tabs left of the notch · template picker + settings right of it
Windows     Onboarding (first run, re-run from Settings) · Settings
Menu bar    icon: Automatic (Macs without a notch) / Always / Never
```

## Sizes

| Panel size | w × h (includes the notch strip) | Padding | Knob | Fader (MIXER) | Artwork |
|---|---|---|---|---|---|
| Compact | 720 × 380 | 16 | 44 | ≥ 172 | 120 |
| Regular (default) | 780 × 420 | 20 | 48 | ≥ 212 | 148 |
| Large | 820 × 460 | 20 | 54 | ≥ 252 | 170 |

- The panel is clamped to the screen width minus 32 pt and to 62 % of the screen height.
- No fader is shorter than 160 pt, and no knob is smaller than 44 pt. Buttons are at least 24 pt.
- The master knob is 96, 112 or 128 pt by panel size.
- Closed notch:
  - Idle: exactly the hardware notch.
  - Playing: two 34 pt wings, with artwork on the left and a static level mark on the right.
  - Hover: grows by 12 pt on each side and 3 pt in height.

## Screens

- **HOME** has three columns.
  - **Now playing:** artwork, title, artist, source and transport. A scrubber appears when the player reports a timeline (Music, Spotify).
  - **Master:** a knob with a stereo meter, mute, and the output device menu.
  - **Playing apps:** icon, name, mini meter and mute for each app. Clicking a row opens MIXER with that strip highlighted. Jump buttons for MIXER and DJ sit underneath.
- **MIXER** shows strips for the playing apps, or every audio app when "Show silent apps" is on. The strips scroll horizontally, and the master strip is pinned on the right.
  - Each strip has an icon, a name, a value, a fader with a meter, M (mute), S (solo) and an output menu.
- **DJ** uses the template's layout. Every template has decks A and B (Minimal has A only), channel volume, CUE (solo) and a crossfader with SMOOTH, DIP and CUT curves (not in Minimal).
  - Tone controls are HI, MID, LOW, FILTER and GAIN. Club leaves out GAIN.
- **Banners** above the tab content show permission requests, a denied permission and errors.

## Interaction

- **Knob**
  - Drag vertically or horizontally; 200 pt covers the full range, and holding ⌥ gives ×0.2 precision.
  - The scroll wheel also adjusts it, with ⌥ for precision.
  - Double-click resets it.
  - Detents at the center and at the kill position, with an `.alignment` haptic.
  - A value bubble shows while dragging or scrolling.
  - VoiceOver can adjust it.
- **Fader**
  - Drags are relative, so a click never jumps the value. ⌥ gives precision, and the scroll wheel works.
  - Double-click sets 100 %.
  - Detent with a haptic at 100 %.
- **Crossfader:** the same as a fader, with a detent at the center. Double-click centers it.
- **Tabs:** click to switch. ⌃⌥M opens MIXER; pressing it again toggles between MIXER and DJ.
- **Close:** the pointer is away for 0.5 s, a click outside, ⌃⌥N, or a click on the notch strip.
- **Right-click** on the notch or the top bar: Settings, Onboarding, Quit.

## Motion

| What | Spec | With Reduce Motion |
|---|---|---|
| Open / close | `spring(response: 0.42, dampingFraction: 0.82)` on size and radii; content fades 0.18 s | 0.15 s ease-out, no spring |
| Hover grow | `spring(response: 0.3, dampingFraction: 0.7)` | none |
| Tab switch | indicator `matchedGeometryEffect`, `spring(0.35, 0.85)`; content slides 12 pt and fades | 0.12 s fade |
| Artwork HOME ↔ DJ | `matchedGeometryEffect` on the playing deck, same spring | none |
| Meters | 30 fps `TimelineView`, only while the panel is open; instant attack, 26 dB/s release, 1 s peak hold then 14 dB/s | unchanged (information) |
| Platter (Club) | 33⅓ rpm while that deck plays | static |
| Onboarding | wordmark letters stagger 45 ms; steps slide 24 pt and fade | fade only |

Idle budget: no timers while the panel is closed. Meter-only taps are removed 2 s after the panel closes.

## Templates

All templates share `AppVolumeMixer`, `NowPlayingMonitor`, `MeterBank` and the controls. They differ in their tokens and their DJ layout.

| Template | Look | DJ layout |
|---|---|---|
| Studio | System accent, light and dark, filled cards, arc knobs, slim faders | Two deck cards with horizontal channel faders, crossfader below |
| K.O. | Off-white `#ECE9E2` or black, orange `#FF5A00`, 1 pt line art, SF Mono | TE grid: deck displays, 2 × 3 line-art knobs per deck, square CUE pads |
| Hardware Black | Matte `#0B0B0C`, white legends, amber LED ring knobs | DJM style: two channel columns with LED meters and vertical faders, master meter in the middle |
| Club | Near black, cyan and magenta decks | Two platters with level history, EQ in the middle, big crossfader |
| Minimal | Follows the system | One deck: artwork, big volume fader, filter knob |

**Tokens** (`ThemeTokens`) cover:

- Colours: `panel`, `surface`, `raised`, `line`, `text`, `secondary`, `tertiary`, `accent`, `onAccent`, `deckA`, `deckB`, and the meter colours (`meterLow`, `meterMid`, `meterHot`, `meterOff`).
- Radii: `panelRadius`, `cardRadius`, `controlRadius`.
- Fonts: `title`, `body`, `label`, `value`, `display`, plus `labelTracking` and `uppercaseLabels`.
- Styles: `knob` (`.arc`, `.line`, `.ledRing`, `.solid`), `fader` (`.slim`, `.line`, `.hardware`, `.thick`), `meter` (`.bar`, `.segments`, `.led`) and `card` (`.filled`, `.outlined`, `.plain`).

**Adding a template:**

1. Add a case to `TemplateID`.
2. Write `struct MyTemplate: DJTemplate`. It provides `tokens(for:)`, `supportsLight`, `name`, `blurb` and `makeDJView(_:)`.
3. Return it from `TemplateID.template`.
4. Add the name and blurb to `en.lproj` and `de.lproj`.

Controls read the tokens from the environment, so HOME, MIXER, Settings and Onboarding pick up the new style without further changes.

## Permissions

- **System Audio Recording (process taps)**
  - Read at launch with the TCC preflight, falling back to the last result Notch DJ saw.
  - Never requested at launch. It is requested only by the onboarding step or when a control that needs a tap is moved.
  - When denied, no tap is attempted. A banner links to Privacy & Security.
- **Automation (Music, Spotify):** macOS asks once, on the first track read.
- **Accessibility (optional):** only needed to send media keys to players that can't be scripted.
- `scripts/setup-signing.sh` gives local builds a stable signature, so these grants survive rebuilds.

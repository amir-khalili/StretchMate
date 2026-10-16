# StretchMate

A native Swift/SwiftUI menu bar app. Every 20 minutes it shows a small floating card (420×320) with animated exercises and step-by-step instructions. No Dock icon, no network access, no dependencies outside Apple frameworks.

By default every break runs the same **neck & shoulder routine**, with the break length split evenly across the three moves:

1. **Neck rotation**: turn to look over each shoulder
2. **Neck forward & back**: chin to chest, then look up
3. **Shoulder rolls**: up, back, down

To get one random exercise per break instead, use **Settings → Each break → One random exercise**. The random pool includes the routine plus neck tilts, chin tucks, shoulder-blade squeeze, 20-20-20 eye break, spinal extension, wrist stretch, hip flexor stretch and a posture check.

Tip: at 30 s each move gets 10 s. For longer holds, set **Break length** to 45–60 s.

## Build & install

```bash
./make.sh            # → build/StretchMate.app (release, universal arm64 + x86_64, ad-hoc signed)
./make.sh install    # also copies it to /Applications and launches it
ARCHS=arm64 ./make.sh  # build for one architecture only
```

Requires the Xcode Command Line Tools (`xcode-select --install`). macOS 14 or later.

To test without waiting 20 minutes:

```bash
open -a StretchMate --args --break-now
```

## Changing the interval

Menu bar icon → **Settings → Break every** → pick a preset, or choose **Custom…** to enter 1–240 minutes. **Break length** works the same way (5–600 s). Changes apply right away.

You can also change them from the terminal, then quit and relaunch the app:

```bash
defaults write com.local.stretchmate intervalMinutes -int 25
defaults write com.local.stretchmate breakSeconds -int 45
defaults write com.local.stretchmate chime -bool true
defaults write com.local.stretchmate mode -string random   # or: routine (default)
```

## Where settings are stored

Settings are stored in UserDefaults under the domain `com.local.stretchmate`, in the file
`~/Library/Preferences/com.local.stretchmate.plist`. To view them, run `defaults read com.local.stretchmate`.

The "Start at login" toggle uses `SMAppService.mainApp`. You can see it in System Settings → General → Login Items.

## Uninstall

```bash
# 1. In the menu: Settings → untick "Start at login"   (or remove it in System Settings → Login Items)
# 2. Quit and delete:
pkill -x StretchMate
rm -rf /Applications/StretchMate.app
defaults delete com.local.stretchmate
```

## When you're away from the Mac

If a break comes due while you're away (screen locked, display asleep, or no keyboard/mouse input for 90 s), the card **stays on screen and waits for you**. It shows a still figure, with no animation or countdown, so it uses 0% CPU. When you unlock or move the mouse, the routine starts and runs for the full break length.

If the Mac was asleep, timers don't run during sleep. On wake or unlock the app checks the real clock, and if a break came due while it was asleep, the card shows right away.

You won't get a pile of cards: after hours away there's just one, waiting.

To change how long without input counts as "away": `defaults write com.local.stretchmate awaySeconds -float 120`, then quit and relaunch.

Diagnostics: `/usr/bin/log stream --info --predicate 'subsystem == "com.local.stretchmate"'` shows when breaks come due, whether you were away, and when the routine started and ended.

## How it stays idle

- There is one `Timer` (tolerance 30 s), set for the next break. It doesn't poll, and it uses no display link or background threads.
- The "Next break in N min" text is worked out only when you open the menu.
- The overlay window exists only during a break. When the break ends, its SwiftUI content is torn down, the window is closed and the reference is set to nil, so no animations run between breaks.
- During a break, the same timer is set again, this time for the end of the break (tolerance 0.5 s so the card closes on time).
- The only extra work while a break waits for you is a mouse and keyboard watcher. It costs nothing until you touch the machine, and it's removed as soon as you're back.
- App Nap is turned off (`NSAppSleepDisabled`) so macOS can't hold back the break timer. With nothing scheduled, that costs nothing.

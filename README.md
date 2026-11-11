# NotchBeat

**[Download NotchBeat for macOS](https://github.com/kboss007/NotchBeat/releases/latest/download/NotchBeat-macOS-Apple-Silicon.zip)** · [Release notes](https://github.com/kboss007/NotchBeat/releases/latest)

NotchBeat is a SwiftUI menu-bar visualizer for macOS 14.2 and later. The included app build targets Apple Silicon. Classic is its only visualizer. Two transparent trails bring the feel of the Apple Music visualizer to the sides of the notch, with layered ribbons, comets, and beat pulses. Each side uses only its matching stereo channel for loudness, bass, sparks, and the waveform envelope drawn from captured samples. On a display without a notch, the trails use the center of the bar as their anchor.

The controls use native Liquid Glass when built with the macOS 26 SDK or newer and run on macOS 26 or later. The palettes, spectrum, and stereo preview are also available with standard controls on older supported releases.


## Download

The prebuilt app requires an Apple Silicon Mac running macOS 14.2 or later.

1. Unzip the download and drag **NotchBeat.app** into **Applications**.
2. Open NotchBeat and look for the island-and-trails icon in the menu bar.
3. Choose **Listen** and allow System Audio Recording when macOS asks.

The release is ad hoc signed. macOS may ask for first-launch approval in Privacy & Security. [Apple’s guide to opening downloaded apps](https://support.apple.com/en-us/102445).

## Use NotchBeat

1. Open NotchBeat.app and click the island-and-trails icon in the menu bar.
2. Under **Audio source**, select **All system audio** or a running app, then click **Start listening**. Allow System Audio Recording if macOS asks and play audio in the chosen app.
3. Choose Stereo for separate left and right signals, or Mono to mirror the combined mix. Switch on Auto color, choose a palette such as B&W, or select a hue on the Spectrum strip. The preview updates with the selected colors and shows live stereo levels when audio arrives.
4. Under **Waveform size**, set **Length**, **Height**, and **Notch gap** using the sliders or by entering values in points. Negative values bring both trails closer, up to the physical notch.

**Match album cover** uses the dominant colors from the current cover in the macOS Music or Spotify app. Allow Automation access if macOS asks. Auto Color takes over if artwork is unavailable. Spotify artwork is retrieved from its cover image URL.

Auto color moves through the spectrum while music plays. The pace responds to loudness and tone, and strong beats move the hue farther. Stereo/Mono changes the visualization only. The Spectrum strip sets a fixed hue. Both trails stay inside the menu bar at the same width, height, and distance from the display midpoint. The display bounds limit the maximum length and height. Use shorter trails if menu items sit close to the notch. The trails stay visible on hover and are click-through. On PROLED XDR MacBook Pros, NotchBeat reserves space around the compact system pill and moves the trails outward when the system exposes a wider onscreen window. Some island states expose only the compact geometry.

Selecting an app filters the visualizer to audio Core Audio attributes to that app and its identifiable helpers. A browser selection applies to the entire browser. If the selected app closes, NotchBeat waits for it to reopen.

For the microphone fallback, select **Microphone** and grant microphone access when prompted. Switching sources while listening restarts capture. **Stop listening** stops capture and hides the trails.

If system audio remains flat while a track is playing, look for NotchBeat in **System Settings → Privacy & Security → Screen & System Audio Recording**. Grant system audio access, then quit and reopen NotchBeat. Some protected playback and audio routed outside the macOS system mix may be unavailable to the tap.

Enable **Low CPU mode** under **Audio source** to use simpler trails at up to 30 fps, analyze half as many audio windows, and check menu-bar placement less often. Playback stays on the same audio tap when you toggle it.

By default, NotchBeat shares one visual update loop targeting 60 fps while audio is active, slows updates while waiting for a signal, and checks island bounds in the background while the trails are active. The Core Audio tap leaves playback audible and processes samples in memory. NotchBeat does not save or transmit audio.

## Build from source

Use macOS with Xcode 15.3 or later or the corresponding Apple Command Line Tools. From the extracted NotchBeat directory:

```sh
./build-app.sh
open .build/NotchBeat.app
```

Pass a destination directory to `build-app.sh` if desired. The script builds for the host architecture, adds the system-audio and microphone privacy descriptions, and signs the bundle ad hoc. Set `NOTCHBEAT_SIGN_IDENTITY` to use a local signing identity instead. The included Apple Silicon build is ad hoc signed for local use.

For editing in Xcode 16 or later, open `Package.swift` and select the **NotchBeat** scheme and **My Mac**. Use the build script to run a bundled build with the required privacy descriptions. The Swift package has no external dependencies.

## Keyboard backlight

macOS exposes keyboard brightness in its settings but does not document a supported API for synchronizing the built-in keyboard backlight to audio. Projects such as [BeatKeys](https://github.com/stevenstewart18-cmd/BeatKeys) use the private CoreBrightness framework for whole-keyboard brightness. That approach is model- and OS-dependent. NotchBeat does not call that framework or change keyboard settings.

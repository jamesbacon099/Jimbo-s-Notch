# Jimbo’s Notch Buddy

Jimbo’s Notch Buddy combines a notch music player and audio visualizers in one macOS menu bar app. It builds on the original [NotchBeat](https://github.com/kboss007/NotchBeat) visualizer.

- **Music Monitor** shows Apple Music or Spotify artwork, a live frequency meter, playback controls, a timeline, and app volume. The player and meter have independent color options.
- **Visualizer** includes Default, Dancers, Fire, Splash, Equalizer, Arcade, and Pulse. Each effect remembers its palette and trail sizing.
- The player and visualizer move together as the player expands. You can choose click or hover to expand the player.

## Download for macOS

Download **Jimbos-Notch-Buddy-macOS-arm64.zip** from the [latest release](https://github.com/jamesbacon099/Jimbo-s-Notch/releases/latest), unzip it, and move **Jimbo’s Notch Buddy.app** into Applications. The download is for Apple Silicon Macs. Intel Macs can build from source.

Open **Jimbo’s Notch Buddy** and click its waveform icon in the menu bar. Choose the **Music Monitor** tab. The standalone **Jimbo’s Notch** app only contains the visualizer.

## Build on macOS

The apps require macOS 14.2 or later and the Xcode command line tools. Run the scripts from the repository root:

```sh
# Combined app with Music Monitor and Visualizer
./build-app.sh

# Standalone visualizer
./build-visualizer.sh

# Standalone music player
./"Jimbo Music"/build-app.sh
```

Each script prints the path to its signed app. Open that app from Finder or drag it to Applications. The combined app uses the music and visualizer sources in this repository.

In Notch Buddy, turn on **Connect to music players** under **Music Monitor** for Apple Music or Spotify. In **Visualizer**, use **Listen** to start capture from your selected audio source. Allow Automation and audio recording when macOS requests them. The Music Monitor meter and the Equalizer effect in Notch Buddy use the connected music app as their source.

The player uses native Liquid Glass when built with the macOS 26 SDK or newer and run on macOS 26 or later. The older macOS fallback uses a translucent material.

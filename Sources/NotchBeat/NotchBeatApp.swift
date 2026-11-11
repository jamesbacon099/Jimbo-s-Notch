import SwiftUI
import AppKit

@main
@MainActor
struct NotchBeatApp: App {
    @StateObject private var audio: AudioMonitor
    @StateObject private var overlay: NotchOverlayController

    init() {
        let audio = AudioMonitor()
        _audio = StateObject(wrappedValue: audio)
        _overlay = StateObject(wrappedValue: NotchOverlayController(audio: audio))
    }

    var body: some Scene {
        MenuBarExtra {
            ScreenBoundSettings {
                NotchBeatControls(audio: audio, overlay: overlay, settings: overlay.settings)
            }
        } label: {
            Image(nsImage: NotchBeatIcon.image)
                .accessibilityLabel("Jimbo's Notch")
        }
        .menuBarExtraStyle(.window)
    }
}

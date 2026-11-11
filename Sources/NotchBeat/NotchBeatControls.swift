import AppKit
import SwiftUI

struct NotchBeatControls: View {
    @ObservedObject var audio: AudioMonitor
    @ObservedObject var overlay: NotchOverlayController
    @ObservedObject var settings: VisualizerSettings
    @State private var appearanceTab = AppearanceTab.colors
    @State private var applications: [AudioApplication] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            header
            channelControl
            LiveSignalPreview(frames: settings.selectedStyle == .equalizer ? overlay.musicSpectrumFrames ?? audio.frames : audio.frames, settings: settings, mode: audio.channelMode, lowPower: audio.lowPower)
            audioControls
                .modifier(ControlCard())
            appearanceControls
                .modifier(ControlCard())
            waveformSize
                .modifier(ControlCard())
            footer
        }
        .padding(15)
        .frame(width: 400)
        .background(alignment: .topLeading) {
            RadialGradient(colors: [settings.basePalette.primary.opacity(0.13), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 260)
                .allowsHitTesting(false)
        }
        .onAppear {
            applications = AudioApplication.choices()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            applications = AudioApplication.choices()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            applications = AudioApplication.choices()
        }
    }

    private enum AppearanceTab: String, CaseIterable {
        case colors = "Colors"
        case visualizer = "Visualizer"
    }

    private var appearanceControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Appearance", selection: $appearanceTab) {
                ForEach(AppearanceTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            if appearanceTab == .colors {
                Toggle("Border fade", isOn: $settings.liquidGlassColors)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                PaletteChooser(settings: settings)
            } else {
                Picker("Visualizer", selection: $settings.selectedStyle) {
                    ForEach(VisualizerStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.menu)
                if settings.selectedStyle.hasSpeed {
                    Slider(value: $settings.effectMotion.speed, in: 0.25...2.5) { Text("Speed") }
                }
                if settings.selectedStyle.hasDensityAndDirection {
                    Slider(value: $settings.effectMotion.density, in: 0.6...2.5) { Text("Density") }
                    Toggle("Reverse direction", isOn: $settings.effectMotion.reversed)
                }
                if settings.selectedStyle == .rainfall {
                    Toggle("Flow from notch", isOn: $settings.rainfallFromNotch)
                    Slider(value: $settings.rainfallDensity, in: 1...3) { Text("Rainfall density") }
                }
                if settings.selectedStyle == .laser {
                    Slider(value: $settings.laserThickness, in: 0.35...1.5) { Text("Laser thickness") }
                        .help("Thinner beams make room for more lasers.")
                }
                if settings.selectedStyle == .splash {
                    Slider(value: $settings.splashDensity, in: 1...3) { Text("Splash density") }
                }
                if settings.selectedStyle == .fire {
                    Slider(value: $settings.plasmaSparks.size, in: 0.35...3) { Text("Spark size") }
                    Slider(value: $settings.plasmaSparks.density, in: 0...3) { Text("Spark density") }
                        .help("Move all the way left to turn sparks off.")
                    Toggle("Flow from notch", isOn: $settings.flowFromNotch)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .font(.caption)
                        .help("Start the effect at the notch edges and send it outward.")
                }
                if settings.selectedStyle == .dancers {
                    Slider(value: $settings.dancerThickness, in: 0.65...2.4) {
                        Text("Dancer thickness")
                    }
                    Toggle("Dancer sparks", isOn: $settings.dancerSparks)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    Picker("Dance style", selection: $settings.relaxedDance) {
                        ForEach(RelaxedDance.allCases, id: \.self) { pose in
                            Text(pose.rawValue).tag(pose)
                        }
                    }
                    Picker("Dancers per side", selection: $settings.dancersPerSide) {
                        ForEach(1...5, id: \.self) { count in
                            Text(count.formatted()).tag(count)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Text(settings.selectedStyle.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Colors and trail size are saved for each effect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(nsImage: NotchBeatIcon.image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24)
                .foregroundStyle(.primary)
                .frame(width: 39, height: 39)
                .modifier(GlassBadge(tint: settings.basePalette.primary))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Jimbo's Notch")
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                Text(audio.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .help(audio.status)
            }
            Spacer()
            listenButton
        }
    }

    private var listenButton: some View {
        Button {
            if audio.running { audio.stop() } else { audio.start() }
        } label: {
            Label(audio.running ? "Stop" : "Listen", systemImage: audio.running ? "stop.fill" : "play.fill")
                .font(.system(size: 12, weight: .semibold))
        }
        .controlSize(.large)
        .modifier(ListenButtonStyle())
        .accessibilityLabel(audio.running ? "Stop listening" : "Start listening")
    }

    private var channelControl: some View {
        HStack(spacing: 10) {
            Text("Channels").font(.callout.weight(.medium))
            Picker("Channel mode", selection: Binding(get: { audio.channelMode }, set: audio.selectMode)) {
                ForEach(ChannelMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Channel mode")
        }
    }

    private var audioControls: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("Audio source", systemImage: "speaker.wave.2")
                    .font(.callout.weight(.semibold))
                Spacer(minLength: 8)
                Picker("Audio source", selection: Binding(get: { audio.source }, set: audio.select)) {
                    Text("All system audio").tag(AudioMonitor.AudioSource.system)
                    Text("Microphone").tag(AudioMonitor.AudioSource.microphone)
                    if case .application(let selected) = audio.source, !applications.contains(selected) {
                        Text(selected.name + " (closed)").tag(AudioMonitor.AudioSource.application(selected))
                    }
                    if !applications.isEmpty {
                        Section("Running apps") {
                            ForEach(applications) { app in
                                Text(app.name).tag(AudioMonitor.AudioSource.application(app))
                            }
                        }
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 205, alignment: .trailing)
            }
            if audio.source != .microphone {
                Picker("Visualizer response", selection: $audio.playbackVolume) {
                    ForEach(AudioMonitor.PlaybackVolume.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .font(.caption)
                .help("Choose whether the visualizer follows the Mac’s volume or responds to captured playback at any volume.")
            }
            HStack(spacing: 8) {
                Text("Sensitivity")
                    .frame(width: 66, alignment: .leading)
                GlassSlider(label: "Sensitivity", value: $audio.sensitivity, range: 0.5...8, step: 0.1,
                            palette: settings.basePalette)
                Text(audio.sensitivity.formatted(.number.precision(.fractionLength(1))))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
            .font(.caption)
            Toggle("Low CPU mode", isOn: $audio.lowPower)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.caption)
                .help("Use simpler trails, fewer redraws, and less frequent audio analysis.")
        }
    }

    private var waveformSize: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("Waveform size", systemImage: "arrow.left.and.right")
                    .font(.callout.weight(.semibold))
                Spacer(minLength: 6)
                if let size = overlay.fittedSize {
                    let width = Double(size.width).formatted(.number.precision(.fractionLength(0...1)))
                    let height = Double(size.height).formatted(.number.precision(.fractionLength(0...1)))
                    Text("\(width) × \(height) pt")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("On-screen size per trail, \(width) by \(height) points")
                        .help("Current on-screen size of each trail")
                }
            }

            sizeSlider("Length", value: $settings.sizing.length, range: TrailSizing.lengthRange)
            sizeSlider("Height", value: $settings.sizing.height, range: TrailSizing.heightRange)
            sizeSlider("Vertical offset", value: $settings.sizing.verticalOffset, range: TrailSizing.verticalOffsetRange)
                .help("Negative moves the visualizer up. Positive moves it down.")
            sizeSlider("Notch gap", value: $settings.sizing.gap, range: overlay.gapRange)
                .help("Move the anchors from the display center to the screen edges. Areas behind the physical camera cutout cannot be displayed.")

            if overlay.isCrowded {
                Text("Waiting for enough room on both sides.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let size = overlay.fittedSize,
                      size.width < settings.sizing.length || size.height < settings.sizing.height {
                Text("Limited by the display dimensions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sizeSlider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        let exactValue = Binding(
            get: { value.wrappedValue },
            set: { value.wrappedValue = min(range.upperBound, max(range.lowerBound, $0.rounded())) }
        )
        return HStack(spacing: 8) {
            Text(label).frame(width: 66, alignment: .leading)
            GlassSlider(label: label, value: value, range: range, step: 1, palette: settings.basePalette)
            TextField(label + " in points", value: exactValue, format: .number.precision(.fractionLength(0)))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 45)
            Text("pt").foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Quit Jimbo's Notch") {
                audio.stop()
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            .keyboardShortcut("q")
        }
        .padding(.horizontal, 3)
    }
}

private struct ControlCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(10)
            .background(.primary.opacity(0.048), in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }
}

private struct GlassBadge: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular.tint(tint.opacity(0.35)), in: .rect(cornerRadius: 13))
        } else {
            content.background(tint.opacity(0.22), in: .rect(cornerRadius: 13))
        }
        #else
        content.background(tint.opacity(0.22), in: .rect(cornerRadius: 13))
        #endif
    }
}

private struct ListenButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
        #else
        content.buttonStyle(.borderedProminent)
        #endif
    }
}

import AppKit
import SwiftUI

struct NotchBeatControls: View {
    @ObservedObject var audio: AudioMonitor
    @ObservedObject var overlay: NotchOverlayController
    @ObservedObject var settings: VisualizerSettings
    @State private var applications: [AudioApplication] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            header
            channelControl
            SignalPreview(frame: audio.frame, palette: settings.palette(for: audio.frame), mode: audio.channelMode)
            audioControls
                .modifier(ControlCard())
            PaletteChooser(settings: settings)
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
            overlay.refreshLayoutAccess()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            applications = AudioApplication.choices()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            applications = AudioApplication.choices()
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
                Text("NotchBeat")
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

            Picker("Waveform size", selection: $overlay.sizing.mode) {
                ForEach(TrailSizing.Mode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Waveform size")

            if overlay.sizing.mode == .manual {
                sizeSlider("Length", value: $overlay.sizing.length, range: TrailSizing.lengthRange)
                sizeSlider("Height", value: $overlay.sizing.height, range: TrailSizing.heightRange)
                if let size = overlay.fittedSize,
                   size.width < overlay.sizing.length || size.height < overlay.sizing.height {
                    Text("Limited by the available menu-bar space.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider().opacity(0.6)
            detection
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

    private var detection: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Menu item detection").font(.caption.weight(.semibold))
                Text(fitDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if !overlay.layoutAccess {
                if overlay.layoutSetupStarted {
                    Button("Open Settings…") { overlay.openLayoutSettings() }
                        .controlSize(.small)
                } else {
                    Button("Set Up…") { overlay.requestLayoutAccess() }
                        .controlSize(.small)
                }
            }
        }
    }

    private var fitDescription: String {
        if overlay.fit == .crowded {
            return "Waiting for enough room on both sides."
        }
        if !overlay.layoutAccess {
            if overlay.layoutSetupStarted {
                return "Turn on NotchBeat in Privacy & Security › Accessibility."
            }
            return overlay.sizing.mode == .manual
                ? "Enable detection to keep longer trails clear of menus."
                : "Enable Accessibility to fit the trails around menus."
        }
        switch overlay.fit {
        case .adaptive: return "Fits both trails in the smaller clear gap."
        case .compact: return overlay.sizing.mode == .manual
            ? "Using your dimensions and the menu positions available."
            : "Using compact size while menu positions are unavailable."
        case .idle: return "Menu item detection is on."
        case .crowded: return "Waiting for enough room on both sides."
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Quit NotchBeat") {
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

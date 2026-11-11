import SwiftUI

struct IslandView: View {
    @ObservedObject var model: MusicModel
    let compactHeight: CGFloat
    let cutoutWidth: CGFloat
    var spectrumView: (() -> AnyView)?
    @State private var scrubbing = false
    @State private var scrubPosition = 0.0

    var body: some View {
        if let size = model.presentedSize {
            surface
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipped()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()
        } else {
            surface
        }
    }

    private var surface: some View {
        ZStack(alignment: .top) {
            Button {
                model.expanded.toggle()
            } label: {
                HStack {
                    cover(size: min(24, compactHeight - 6))
                    Spacer(minLength: 0)
                    Group {
                        if let spectrumView {
                            spectrumView()
                        } else {
                            Image(systemName: model.track?.playing == true ? "waveform" : "music.note")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(model.accent)
                        }
                    }
                    .frame(width: 25, height: 19)
                }
                .padding(.horizontal, 11)
                .frame(maxWidth: .infinity)
                .frame(height: compactHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.expanded ? "Collapse music player" : "Expand music player")

            if model.expanded {
                VStack(spacing: 10) {
                    HStack(spacing: 11) {
                        cover(size: 46)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                            Text(model.artist).font(.caption).foregroundStyle(.white.opacity(0.64)).lineLimit(1)
                        }
                        Spacer()
                        Text(model.track?.player.name ?? "Preview")
                            .font(.caption2).foregroundStyle(model.accent)
                    }
                    Slider(value: Binding(get: { scrubbing ? scrubPosition : model.progress },
                                          set: { scrubPosition = $0 }),
                           in: 0...max(1, model.duration), onEditingChanged: { editing in
                        if editing { scrubPosition = model.progress }
                        else { model.seek(scrubPosition) }
                        scrubbing = editing
                    })
                    .tint(model.accent)
                    .accessibilityLabel("Playback position")
                    HStack {
                        Text(timestamp(scrubbing ? scrubPosition : model.progress))
                        Spacer()
                        Text(timestamp(model.duration))
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
                    HStack(spacing: 26) {
                        transport("Previous track", "backward.fill", "previous track")
                        transport(model.track?.playing == true ? "Pause" : "Play",
                                  model.track?.playing == true ? "pause.fill" : "play.fill", "playpause")
                        transport("Next track", "forward.fill", "next track")
                    }
                    .font(.system(size: 18, weight: .semibold))
                    HStack(spacing: 8) {
                        Image(systemName: (model.playerVolume ?? 0) == 0 ? "speaker.slash" : "speaker.wave.2")
                            .frame(width: 18)
                            .accessibilityHidden(true)
                        Slider(value: Binding(get: { model.playerVolume ?? 0 }, set: model.setPlayerVolume),
                               in: 0...100, step: 1)
                            .tint(model.accent)
                            .accessibilityLabel((model.track?.player.name ?? "Player") + " volume")
                        Text("\(Int(model.playerVolume ?? 0))%")
                            .monospacedDigit()
                            .frame(width: 34, alignment: .trailing)
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.78))
                    .disabled(model.playerVolume == nil)
                }
                .padding(.horizontal, 17)
                .padding(.top, compactHeight + 5)
                .padding(.bottom, 12)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
        .background { playerBackground }
        .clipped()
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.18), value: model.expanded)
    }

    private var playerShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: model.radius,
                               bottomTrailingRadius: model.radius, topTrailingRadius: 6)
    }

    @ViewBuilder
    private var playerBackground: some View {
        if model.liquidGlassPlayer {
            GeometryReader { geometry in
                let centerWidth = min(0.46, cutoutWidth / (2 * max(1, geometry.size.width)))
                ZStack {
                    glassSurface
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.5 - centerWidth),
                        .init(color: .black, location: 0.5 + centerWidth),
                        .init(color: .clear, location: 1)
                    ], startPoint: .leading, endPoint: .trailing)
                    .clipShape(playerShape)
                }
            }
        } else {
            playerShape.fill(.black)
        }
    }

    @ViewBuilder
    private var glassSurface: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.clear.tint(model.glassTint.opacity(0.30)), in: playerShape)
        } else {
            playerShape.fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                .overlay { playerShape.fill(model.glassTint.opacity(0.20)) }
        }
        #else
        playerShape.fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                .overlay { playerShape.fill(model.glassTint.opacity(0.20)) }
        #endif
    }

    private func cover(size: CGFloat) -> some View {
        Group {
            if let artwork = model.artwork {
                Image(nsImage: artwork).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [model.accent.opacity(0.75), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note").font(.system(size: size * 0.47, weight: .semibold))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.22))
        .accessibilityHidden(true)
    }

    private func transport(_ label: String, _ icon: String, _ command: String) -> some View {
        Button { model.command(command) } label: { Image(systemName: icon).frame(width: 24, height: 25) }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
    }

    private func timestamp(_ seconds: Double) -> String {
        let value = Int(seconds)
        return "\(value / 60):" + String(format: "%02d", value % 60)
    }
}

struct SettingsView: View {
    @ObservedObject var model: MusicModel
    var appName = "Jimbo Music"
    var visualizerTheme: Color?
    var equalizerColorControls: AnyView?

    var body: some View {
        if let visualizerTheme {
            controls
                .padding(12)
                .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.08))
                        .allowsHitTesting(false)
                }
                .padding(15)
                .frame(width: 400)
                .background(alignment: .topLeading) {
                    RadialGradient(colors: [visualizerTheme.opacity(0.13), .clear],
                                   center: .topLeading, startRadius: 0, endRadius: 260)
                        .allowsHitTesting(false)
                }
        } else {
            controls.padding(16).frame(width: 320)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(appName).font(.title2.bold())
            Text(model.status).font(.caption).foregroundStyle(.secondary)
            Picker("Player", selection: $model.source) {
                Text("Auto").tag("Auto")
                ForEach(Player.allCases) { Text($0.name).tag($0.rawValue) }
            }
            Toggle("Connect to music players", isOn: $model.connected)
            Divider()
            Toggle("Liquid Glass player", isOn: $model.liquidGlassPlayer)
            if model.liquidGlassPlayer, model.visualizerTint != nil {
                Picker("Glass tint", selection: $model.glassTintSource) {
                    ForEach(["Album cover", "Visualizer", "Accent"], id: \.self) { Text($0) }
                }
            }
            equalizerColorControls
            Picker("Accent", selection: $model.tint) {
                ForEach((visualizerTheme == nil ? [] : ["Auto"]) + ["Album cover", "Custom", "Violet", "Mint", "Coral", "Ice", "White"], id: \.self) { Text($0) }
            }
            if model.tint == "Custom" {
                HStack {
                    Text("Accent hue")
                    Slider(value: $model.accentHue, in: 0...1)
                        .tint(model.accent)
                        .accessibilityLabel("Accent hue")
                    Circle().fill(model.accent).frame(width: 16, height: 16)
                        .accessibilityHidden(true)
                }
            }
            setting("Compact width", value: $model.shoulder, range: 32...76)
            setting("Player width", value: $model.width, range: 300...520)
            setting("Corner radius", value: $model.radius, range: 8...32)
            if appName == "Jimbo Music", NSScreen.screens.allSatisfy({ $0.safeAreaInsets.top == 0 }) {
                setting("Top offset", value: $model.bottomGap, range: 0...36)
            }
            if appName == "Jimbo Music" {
                Toggle("Expand on hover", isOn: $model.onHover)
            } else {
                Picker("Expand player", selection: $model.studioOnHover) {
                    Text("Click").tag(false)
                    Text("Hover").tag(true)
                }
                .pickerStyle(.segmented)
            }
            Toggle("Show paused tracks", isOn: $model.showPaused)
            Divider()
            HStack {
                if visualizerTheme == nil {
                    Button(model.preview ? "Hide preview" : "Preview player") { model.preview.toggle() }
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
            }
        }
    }

    private func setting(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title).frame(width: 101, alignment: .leading)
            Slider(value: value, in: range, step: 1).accessibilityLabel(title)
            Text(value.wrappedValue, format: .number.precision(.fractionLength(0)))
                .monospacedDigit().foregroundStyle(.secondary).frame(width: 28, alignment: .trailing)
        }
        .font(.caption)
    }
}

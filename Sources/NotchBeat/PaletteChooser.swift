import SwiftUI

struct PaletteChooser: View {
    @ObservedObject var settings: VisualizerSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Colors", systemImage: "paintpalette")
                    .font(.callout.weight(.semibold))
                Spacer()
                Toggle("Keep color settings", isOn: $settings.keepColorSettings)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.caption)
                    .help("Use the same palette and Spectrum hue across visualizers.")
            }
            HStack(spacing: 14) {
                Toggle("Rainbow", isOn: Binding(
                    get: { settings.selectedPalette == .automatic },
                    set: settings.setAutoColor
                ))
                .help("Shift the palette with bass, treble, and beats.")

                Toggle("Match album cover", isOn: Binding(
                    get: { settings.selectedPalette == .albumArt },
                    set: { enabled in
                        if enabled { settings.selectedPalette = .albumArt }
                        else { settings.setAutoColor(false) }
                    }
                ))
                .help("Matches the cover in Music or Spotify. Uses Rainbow when no cover is available.")
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .font(.caption)

            if settings.selectedPalette == .albumArt {
                Text(settings.artworkColors == nil ? "Using Rainbow until artwork is available." : "Using album cover colors.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 5), spacing: 8) {
                ForEach(VisualizerPalette.allCases.filter { $0 != .spectrum && $0 != .automatic && $0 != .albumArt }) { palette in
                    swatch(palette)
                }
            }
            SpectrumStrip(settings: settings)
        }
    }

    private func swatch(_ palette: VisualizerPalette) -> some View {
        let selected = settings.selectedPalette == palette
        return Button {
            settings.selectedPalette = palette
        } label: {
            VStack(spacing: 4) {
                Circle()
                    .fill(LinearGradient(colors: palette.colors.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay {
                        Circle()
                            .fill(RadialGradient(colors: [.white.opacity(0.65), .clear],
                                                 center: UnitPoint(x: 0.31, y: 0.22), startRadius: 0, endRadius: 14))
                    }
                    .overlay { Circle().strokeBorder(.white.opacity(0.32), lineWidth: 1) }
                    .overlay(alignment: .bottomTrailing) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color(white: 0.10))
                                .offset(x: 2, y: 2)
                        }
                    }
                    .frame(width: 27, height: 27)
                Text(palette.rawValue)
                    .font(.system(size: 10, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(.primary.opacity(selected ? 0.09 : 0), in: .rect(cornerRadius: 11))
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(.primary.opacity(selected ? 0.13 : 0), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(palette == .blackAndWhite ? "Black and white" : palette.rawValue)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct SpectrumStrip: View {
    @ObservedObject var settings: VisualizerSettings

    private static let colors = (0...12).map {
        Color(hue: Double($0) / 12, saturation: 0.76, brightness: 1)
    }

    private var selected: Bool { settings.selectedPalette == .spectrum }

    var body: some View {
        HStack(spacing: 10) {
            Text("Spectrum")
                .font(.caption.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? .primary : .secondary)
                .accessibilityHidden(true)
            GeometryReader { geometry in
                let inset: CGFloat = 7
                let span = max(1, geometry.size.width - 2 * inset)
                Capsule()
                    .fill(LinearGradient(colors: Self.colors, startPoint: .leading, endPoint: .trailing))
                    .overlay { Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1) }
                    .frame(height: 12)
                    .frame(maxHeight: .infinity)
                    .overlay(alignment: .leading) {
                        Circle()
                            .fill(Color(hue: settings.spectrumHue, saturation: 0.76, brightness: 1))
                            .overlay { Circle().strokeBorder(.white, lineWidth: 2) }
                            .frame(width: 14, height: 14)
                            .opacity(selected ? 1 : 0.5)
                            .offset(x: settings.spectrumHue * span)
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { settings.selectSpectrum(($0.location.x - inset) / span, persist: false) }
                        .onEnded { settings.selectSpectrum(($0.location.x - inset) / span, persist: true) })
            }
            .frame(height: 20)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Color spectrum")
        .accessibilityValue("\(Int((settings.spectrumHue * 360).rounded())) degrees")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: adjust(1)
            case .decrement: adjust(-1)
            @unknown default: break
            }
        }
        .focusable()
        .onMoveCommand { direction in
            switch direction {
            case .left, .down: adjust(-1)
            case .right, .up: adjust(1)
            @unknown default: break
            }
        }
    }

    private func adjust(_ direction: Double) {
        settings.selectSpectrum(settings.spectrumHue + direction / 36, persist: true)
    }
}

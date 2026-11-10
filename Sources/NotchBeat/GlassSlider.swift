import SwiftUI

struct GlassSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let palette: TrailPalette

    @FocusState private var focused: Bool
    @State private var hovering = false
    @GestureState private var dragging = false

    private var active: Bool { hovering || dragging || focused }

    var body: some View {
        GeometryReader { geometry in
            let inset: CGFloat = 9
            let travel = max(1, geometry.size.width - inset * 2)
            let fraction = min(1, max(0, (value - range.lowerBound) / (range.upperBound - range.lowerBound)))
            let offset = travel * fraction

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.primary.opacity(0.13))
                    .overlay { Capsule().strokeBorder(.primary.opacity(0.12), lineWidth: 1) }
                    .frame(width: travel, height: 6)
                    .offset(x: inset)
                if offset > 0 {
                    Capsule()
                        .fill(LinearGradient(colors: [palette.secondary, palette.primary, palette.highlight],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: offset, height: 6)
                        .shadow(color: palette.primary.opacity(active ? 0.44 : 0.24), radius: 3)
                        .offset(x: inset)
                }
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Circle().fill(RadialGradient(colors: [.white.opacity(0.56), palette.primary.opacity(0.35)],
                                                    center: .topLeading, startRadius: 0, endRadius: 18))
                    }
                    .overlay { Circle().strokeBorder(.white.opacity(focused ? 0.95 : 0.68), lineWidth: focused ? 1.5 : 1) }
                    .frame(width: 16, height: 16)
                    .scaleEffect(active ? 1.12 : 1)
                    .shadow(color: palette.primary.opacity(active ? 0.48 : 0.22), radius: 4)
                    .offset(x: inset + offset - 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .updating($dragging) { _, active, _ in active = true }
                .onChanged {
                    if !focused { focused = true }
                    let fraction = min(1, max(0, ($0.location.x - inset) / travel))
                    setValue(range.lowerBound + fraction * (range.upperBound - range.lowerBound))
                })
        }
        .frame(height: 23)
        .onHover { hovering = $0 }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .animation(.easeOut(duration: 0.15), value: active)
        .onMoveCommand { direction in
            switch direction {
            case .left, .down: setValue(value - step)
            case .right, .up: setValue(value + step)
            @unknown default: break
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value.formatted(.number.precision(.fractionLength(0...1))))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: setValue(value + step)
            case .decrement: setValue(value - step)
            @unknown default: break
            }
        }
    }

    private func setValue(_ proposed: Double) {
        let rounded = range.lowerBound + ((proposed - range.lowerBound) / step).rounded() * step
        let next = min(range.upperBound, max(range.lowerBound, rounded))
        if next != value { value = next }
    }
}

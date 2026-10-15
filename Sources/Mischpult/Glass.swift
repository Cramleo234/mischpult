import SwiftUI

// Liquid Glass ab macOS 26; davor ein ähnlich wirkendes Material.

extension View {
    /// Glas-Kachel wie die Module im Kontrollzentrum.
    @ViewBuilder
    func glassTile(cornerRadius: CGFloat = 20, tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular.tint(tint), in: .rect(cornerRadius: cornerRadius))
        } else {
            background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        if let tint {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(tint.opacity(0.18))
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(.white.opacity(0.12))
                    }
            }
        }
    }

    /// Runder Glas-Knopf (z. B. Gerätesymbol, Optionen).
    @ViewBuilder
    func glassCircle(tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular.tint(tint).interactive(interactive), in: .circle)
        } else {
            background {
                Circle()
                    .fill(.thickMaterial)
                    .overlay { if let tint { Circle().fill(tint.opacity(0.85)) } }
                    .overlay { Circle().strokeBorder(.white.opacity(0.14)) }
            }
        }
    }

    /// Knopf im Glas-Stil (Systemstil unter macOS 26, sonst „bordered“).
    @ViewBuilder
    func glassButtonStyle(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }
}

/// Fasst Glas-Elemente zusammen, damit sie wie eine Fläche ineinanderfließen.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 10
    @ViewBuilder let content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

/// Breiter Schieberegler wie im Kontrollzentrum.
///
/// - `origin`: Startpunkt der Füllung (0 für Lautstärke, Mitte für den Equalizer).
/// - `mark`: Markierung (100 %); oberhalb davon wird orange gefüllt (Verstärkung).
struct PillSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var origin: Double? = nil
    var mark: Double? = nil
    var symbol: String? = nil
    var height: CGFloat = 26
    var dimmed = false
    var accessibilityLabel: Text = Text("")
    var accessibilityValue: String = ""
    var step: Double = 0.05
    var onSymbolTap: (() -> Void)? = nil

    @State private var dragging = false

    private func fraction(_ v: Double) -> CGFloat {
        CGFloat((min(max(v, range.lowerBound), range.upperBound) - range.lowerBound)
                / (range.upperBound - range.lowerBound))
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let start = fraction(origin ?? range.lowerBound) * width
            let end = fraction(value) * width
            let markX = mark.map { fraction($0) * width }
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10))
                // Normale Füllung bis zur Markierung …
                fillShape(from: min(start, end), to: min(max(start, end), markX ?? width), width: width)
                    .fill(.white.opacity(dimmed ? 0.45 : 0.95))
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                // … darüber orange (Verstärkung).
                if let markX, end > markX {
                    fillShape(from: markX, to: end, width: width)
                        .fill(LinearGradient(colors: [.orange.opacity(0.85), .orange],
                                             startPoint: .leading, endPoint: .trailing))
                        .opacity(dimmed ? 0.5 : 1)
                }
                if let markX {
                    Capsule()
                        .fill(Color.primary.opacity(0.28))
                        .frame(width: 2, height: height * 0.42)
                        .offset(x: markX - 1)
                }
                if let symbol {
                    let covered = end > height * 0.95
                    Image(systemName: symbol)
                        .font(.system(size: height * 0.46, weight: .semibold))
                        .foregroundStyle(covered ? AnyShapeStyle(Color.black.opacity(0.62))
                                                 : AnyShapeStyle(.secondary))
                        .frame(width: height, height: height)
                        .contentShape(Rectangle())
                        .onTapGesture { onSymbolTap?() }
                }
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
            .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                // Ein Klick auf das Symbol schaltet stumm und verschiebt den Regler nicht.
                if onSymbolTap != nil && gesture.startLocation.x < height { return }
                dragging = true
                let ratio = Double(min(max(gesture.location.x / max(width, 1), 0), 1))
                var newValue = range.lowerBound + ratio * (range.upperBound - range.lowerBound)
                // Leicht an der Markierung / am Ursprung einrasten.
                let snapWidth = (range.upperBound - range.lowerBound) * 0.025
                if let mark, abs(newValue - mark) < snapWidth { newValue = mark }
                if let origin, abs(newValue - origin) < snapWidth { newValue = origin }
                value = newValue
            }.onEnded { _ in dragging = false })
        }
        .frame(height: height)
        .scaleEffect(y: dragging ? 1.08 : 1, anchor: .center)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: dragging)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + step, range.upperBound)
            case .decrement: value = max(value - step, range.lowerBound)
            @unknown default: break
            }
        }
    }

    private func fillShape(from: CGFloat, to: CGFloat, width: CGFloat) -> Path {
        Path(CGRect(x: from, y: 0, width: max(to - from, 0), height: height))
    }
}

/// Dünne Pegelanzeige unter einem Regler.
struct LevelBar: View {
    let level: Float

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [.green, .yellow, .orange],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: proxy.size.width * CGFloat(min(level, 1)))
                    .mask(alignment: .leading) { Capsule() }
            }
        }
        .frame(height: 3)
        .opacity(level > 0 ? 1 : 0.5)
        .accessibilityHidden(true)
    }
}

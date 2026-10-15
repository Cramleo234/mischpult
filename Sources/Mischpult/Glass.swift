import SwiftUI

// Liquid Glass ab macOS 26; davor ein ähnlich wirkendes Material.

/// Glas-Intensität 0 … 1 (Einstellung „Glas-Intensität“).
/// 1 = volles Liquid Glass, 0 = fast deckende, ruhige Flächen.
enum GlassSettings {
    static let key = "glassIntensity"
    static let defaultIntensity = 1.0
}

private struct GlassIntensityKey: EnvironmentKey {
    static let defaultValue = GlassSettings.defaultIntensity
}

extension EnvironmentValues {
    var glassIntensity: Double {
        get { self[GlassIntensityKey.self] }
        set { self[GlassIntensityKey.self] = newValue }
    }
}

/// Deckschicht zwischen Glas und Inhalt: je geringer die Intensität, desto
/// weniger scheint der Hintergrund durch.
private func frost(_ intensity: Double) -> Color {
    Color(nsColor: .windowBackgroundColor).opacity((1 - min(max(intensity, 0), 1)) * 0.92)
}

private struct GlassTileModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?
    @Environment(\.glassIntensity) private var intensity

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            content
                .background(shape.fill(frost(intensity)))
                .glassEffect(.regular.tint(tint), in: shape)
        } else {
            content.background {
                shape.fill(.regularMaterial)
                    .overlay { shape.fill(frost(intensity)) }
                    .overlay { if let tint { shape.fill(tint.opacity(0.18)) } }
                    .overlay { shape.strokeBorder(.white.opacity(0.12)) }
            }
        }
    }
}

private struct GlassCircleModifier: ViewModifier {
    let tint: Color?
    let interactive: Bool
    @Environment(\.glassIntensity) private var intensity

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .background(Circle().fill(tint == nil ? frost(intensity) : .clear))
                .glassEffect(.regular.tint(tint).interactive(interactive), in: .circle)
        } else {
            content.background {
                Circle()
                    .fill(.thickMaterial)
                    .overlay { if tint == nil { Circle().fill(frost(intensity)) } }
                    .overlay { if let tint { Circle().fill(tint.opacity(0.85)) } }
                    .overlay { Circle().strokeBorder(.white.opacity(0.14)) }
            }
        }
    }
}

extension View {
    /// Glas-Kachel wie die Module im Kontrollzentrum.
    func glassTile(cornerRadius: CGFloat = 20, tint: Color? = nil) -> some View {
        modifier(GlassTileModifier(cornerRadius: cornerRadius, tint: tint))
    }

    /// Runder Glas-Knopf (z. B. Gerätesymbol, Optionen).
    func glassCircle(tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassCircleModifier(tint: tint, interactive: interactive))
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

/// Dünne Pegelanzeige unter einem Regler.
struct LevelBar: View {
    let level: Float

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(LinearGradient(colors: [.green, .yellow, .orange],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: proxy.size.width * CGFloat(min(level, 1)))
                    .mask(alignment: .leading) { Capsule() }
            }
        }
        .frame(height: 3)
        .opacity(level > 0 ? 1 : 0.4)
        .accessibilityHidden(true)
    }
}

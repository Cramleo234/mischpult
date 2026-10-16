import AppKit
import SwiftUI

/// Glas-Intensität 0 … 1 (Einstellung „Glas-Intensität“).
///
/// Das Menüleisten-Fenster ist unter macOS bereits eine Glasfläche. Die Intensität
/// legt eine Deckschicht darüber: 1 = volles Glas, 0 = ruhige, fast deckende Fläche.
enum GlassSettings {
    static let key = "glassIntensity"
    static let defaultIntensity = 1.0

    static func backdrop(_ intensity: Double) -> Color {
        Color(nsColor: .windowBackgroundColor).opacity((1 - min(max(intensity, 0), 1)) * 0.92)
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

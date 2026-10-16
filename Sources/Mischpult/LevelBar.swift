import SwiftUI

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

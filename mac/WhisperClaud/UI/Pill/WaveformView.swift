import SwiftUI

struct WaveformView: View {
    let levels: [Float]
    var tint: Color = .white

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(levels.indices, id: \.self) { index in
                Capsule()
                    .fill(tint.opacity(0.9))
                    .frame(width: 3, height: 4 + CGFloat(min(1, levels[index])) * 20)
            }
        }
        .frame(height: 26)
        .animation(.linear(duration: 0.07), value: levels)
    }
}

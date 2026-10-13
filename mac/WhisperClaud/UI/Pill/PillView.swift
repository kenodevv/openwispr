import SwiftUI

/// The floating capsule at the bottom of the screen (Wispr-Flow style).
struct PillView: View {
    let state: AppState

    var body: some View {
        HStack(spacing: 10) {
            content
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .frame(height: 42)
        .background(Capsule().fill(Color.black.opacity(0.84)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 5)
        .animation(.spring(duration: 0.25), value: state.pipeline)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        switch state.pipeline {
        case .recording(let mode, let handsFree):
            RecordingDot(color: mode == .command ? .purple : .red)
            WaveformView(levels: state.levels, tint: mode == .command ? .purple : .white)
            if mode == .command {
                Text("Befehl").foregroundStyle(.purple)
            } else if handsFree {
                Text("Freisprechen").foregroundStyle(.white.opacity(0.7))
            }
        case .transcribing:
            ProgressView().controlSize(.small).tint(.white)
            Text("Transkribiere…")
        case .formatting:
            Image(systemName: "sparkles").foregroundStyle(.yellow)
            Text("Formatiere…")
        case .inserting:
            Image(systemName: "text.cursor")
            Text("Füge ein…")
        case .done(let preview):
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text(preview.isEmpty ? "Fertig" : preview).lineLimit(1).frame(maxWidth: 360)
        case .notice(let message):
            Image(systemName: "info.circle").foregroundStyle(.white.opacity(0.8))
            Text(message).lineLimit(1)
        case .error(let message):
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text(message).lineLimit(1).frame(maxWidth: 420)
        case .idle:
            EmptyView()
        }
    }
}

private struct RecordingDot: View {
    let color: Color
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .scaleEffect(pulse ? 1.25 : 0.9)
            .opacity(pulse ? 1 : 0.6)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }
            }
    }
}

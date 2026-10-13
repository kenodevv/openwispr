import SwiftUI

/// The floating capsule at the bottom of the screen. Monochrome: everything is white on black.
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
            RecordingDot()
            WaveformView(levels: state.levels)
            if mode == .command {
                Text("Command")
            } else if handsFree {
                Text("Hands-free").opacity(0.7)
            }
        case .transcribing:
            ProgressView().controlSize(.small).tint(.white)
            Text("Transcribing…")
        case .formatting:
            ProgressView().controlSize(.small).tint(.white)
            Text("Formatting…")
        case .inserting:
            ProgressView().controlSize(.small).tint(.white)
            Text("Inserting…")
        case .done(let preview):
            Image(systemName: "checkmark.circle")
            Text(preview.isEmpty ? "Done" : preview).lineLimit(1).frame(maxWidth: 360)
        case .notice(let message):
            Image(systemName: "info.circle")
            Text(message).lineLimit(1).frame(maxWidth: 420)
        case .error(let message):
            Image(systemName: "exclamationmark.circle")
            Text(message).lineLimit(1).frame(maxWidth: 420)
        case .idle:
            EmptyView()
        }
    }
}

private struct RecordingDot: View {
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(.white)
            .frame(width: 9, height: 9)
            .scaleEffect(pulse ? 1.25 : 0.9)
            .opacity(pulse ? 1 : 0.55)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }
            }
    }
}

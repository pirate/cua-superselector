import AppKit
import Observation
import SwiftUI

@Observable
final class RecordingControlState {
  var isPaused = false
  @ObservationIgnored var onReset: (() -> Void)?
  @ObservationIgnored var onPauseChanged: ((Bool) -> Void)?
  @ObservationIgnored var onEnd: (() -> Void)?
}

struct RecordingControlView: View {
  @Bindable var state: RecordingControlState

  var body: some View {
    Group {
      if #available(macOS 26.0, *) {
        controls
          .padding(7)
          .glassEffect(.regular, in: .capsule)
      } else {
        controls
          .padding(7)
          .background(.regularMaterial, in: Capsule())
          .overlay(Capsule().stroke(.white.opacity(0.14)))
      }
    }
    .padding(5)
  }

  private var controls: some View {
    HStack(spacing: 7) {
      Button("Reset", systemImage: "arrow.counterclockwise") {
        state.onReset?()
      }
      Divider().frame(height: 17)
      Button(
        state.isPaused ? "Resume" : "Pause",
        systemImage: state.isPaused ? "play.fill" : "pause.fill"
      ) {
        state.isPaused.toggle()
        state.onPauseChanged?(state.isPaused)
      }
      Divider().frame(height: 17)
      Button("End", systemImage: "stop.fill", role: .destructive) {
        state.onEnd?()
      }
      .foregroundStyle(.pink)
    }
    .font(.system(size: 12, weight: .semibold))
    .buttonStyle(.borderless)
    .controlSize(.small)
  }
}

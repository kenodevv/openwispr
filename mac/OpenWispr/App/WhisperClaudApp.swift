import SwiftUI

@main
struct OpenWisprApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    private var container: AppContainer { AppContainer.shared }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(container.state)
                .environment(container.settings)
        } label: {
            MenuBarLabel(state: container.state)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environment(container.state)
                .environment(container.settings)
                .modelContainer(container.store.container)
        }
    }
}

struct MenuBarLabel: View {
    let state: AppState

    var body: some View {
        Image(systemName: symbol)
    }

    private var symbol: String {
        switch state.pipeline {
        case .recording: return "waveform.circle.fill"
        case .transcribing, .formatting, .inserting: return "waveform.badge.magnifyingglass"
        case .error: return "waveform.badge.exclamationmark"
        default: return "waveform"
        }
    }
}

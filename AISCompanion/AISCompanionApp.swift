import SwiftUI

@main
struct AISCompanionApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            TalkView()
                .tabItem { Label("Talk", systemImage: "mic.circle") }
            EventsView()
                .tabItem { Label("Events", systemImage: "waveform.path.ecg") }
            StatusView()
                .tabItem { Label("Status", systemImage: "gauge.with.dots.needle.50percent") }
            TasksView()
                .tabItem { Label("Tasks", systemImage: "checklist") }
            SettingsView()
                .tabItem { Label("Host", systemImage: "network") }
        }
        .tint(Theme.accent)
    }
}

enum Theme {
    static let bg = Color(red: 0.039, green: 0.055, blue: 0.078)
    static let surface = Color(red: 0.067, green: 0.094, blue: 0.137)
    static let accent = Color(red: 0.176, green: 0.831, blue: 0.749)
    static let warn = Color(red: 0.961, green: 0.620, blue: 0.043)
    static let bad = Color(red: 0.937, green: 0.267, blue: 0.267)
    static let good = Color(red: 0.133, green: 0.773, blue: 0.369)
    static let dim = Color(red: 0.431, green: 0.482, blue: 0.545)
    static let text = Color(red: 0.902, green: 0.929, blue: 0.953)
}

extension View {
    func card() -> some View {
        self.padding(12)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.08)))
    }
}

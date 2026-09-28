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
            LearnView()
                .tabItem { Label("Learn", systemImage: "brain.head.profile") }
            JarvisView()
                .tabItem { Label("Jarvis", systemImage: "waveform.circle") }
            SystemView()
                .tabItem { Label("System", systemImage: "gauge.with.dots.needle.50percent") }
        }
        .tint(Theme.accent)
    }
}

/// Host configuration, health dashboard, and task control.
///
/// Host settings live here rather than in the tab bar so the five primary
/// destinations stay one-thumb reachable.
struct SystemView: View {
    @State private var health = LoadState<Health>.idle
    @State private var tasks = LoadState<[String: Any]>.idle
    @State private var latest = LoadState<EventEnvelope?>.idle
    @State private var newTask = ""
    @State private var busy = false
    private let api = AisApi()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        healthCard
                        latestCard
                        tasksCard
                        SettingsContent()
                    }
                    .padding(14)
                }
            }
            .navigationTitle("SYSTEM")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { load() } label: { Image(systemName: "arrow.clockwise") }
                }
            }
            .task { load() }
        }
    }

    private var healthCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel("HEALTH \u{00B7} GET /health")
                Spacer()
                StateBanner(state: health)
            }
            if case .loaded(let h) = health {
                KV(key: "status", value: h.statusLabel ?? h.status ?? "",
                   tint: (h.status == "HEALTHY") ? Theme.good : Theme.warn)
                KV(key: "provenance", value: h.provenance ?? "")
                metrics("MODELS", h.models)
                metrics("PROVIDERS", h.providers)
                metrics("TESTING", h.testing)
                metrics("LAYA", h.laya)
            } else {
                Text(health.detail).font(.caption2).foregroundColor(health.tint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    /// A NULL metric is UNMEASURED. It is never rendered as 0.
    private func metrics(_ label: String, _ m: Health.Metrics?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            SectionLabel(label)
            if let m {
                KV(key: "healthy/total", value: "\(m.healthy.map(String.init) ?? "?")/\(m.registered.map(String.init) ?? "?")")
                KV(key: "pass_rate", value: m.passRate.map { String(format: "%.3f", $0) } ?? "UNMEASURED")
                KV(key: "decisions", value: m.totalDecisions.map(String.init) ?? "UNMEASURED")
                KV(key: "latency", value: m.meanLatencyMs.map { String(format: "%.2f ms", $0) } ?? "UNMEASURED")
            } else {
                Text("UNMEASURED")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Theme.dim)
            }
        }
    }

    private var latestCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel("LATEST EVENT \u{00B7} GET /events/latest")
                Spacer()
                StateBanner(state: latest)
            }
            switch latest {
            case .loaded(let e):
                if let e { EventCard(index: 0, event: e) }
                else {
                    Text("No events recorded yet. This is an empty state, not a failure.")
                        .font(.caption2).foregroundColor(Theme.dim)
                }
            case .unreachable, .rejected:
                Text(latest.detail).font(.caption2).foregroundColor(latest.tint)
            default: EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var tasksCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("TASKS \u{00B7} POST /tasks")
                Spacer()
                StateBanner(state: tasks)
            }
            HStack {
                TextField("new task title", text: $newTask)
                    .textFieldStyle(.roundedBorder)
                Button("ADD") { addTask() }
                    .buttonStyle(.bordered).tint(Theme.accent)
                    .disabled(newTask.isEmpty || busy)
            }
            if case .loaded(let o) = tasks {
                KV(key: "payload", value: JarvisView.render(o))
            } else if case .unreachable = tasks {
                Text(tasks.detail).font(.caption2).foregroundColor(Theme.warn)
            } else if case .rejected = tasks {
                Text(tasks.detail).font(.caption2).foregroundColor(Theme.bad)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func load() {
        Task {
            async let a = fetchHealth()
            async let b = fetchLatest()
            _ = await (a, b)
        }
    }

    private func fetchHealth() async {
        health = .loading
        do { health = .loaded(try await api.health()) }
        catch { health = stateFor(error) }
    }

    private func fetchLatest() async {
        latest = .loading
        do { latest = .loaded(try await api.latestEvent()) }
        catch { latest = stateFor(error) }
    }

    private func addTask() {
        busy = true
        Task {
            defer { busy = false }
            do {
                try await api.createTask(newTask)
                newTask = ""
                tasks = .loaded(try await api.tasks())
            } catch {
                tasks = stateFor(error)
            }
        }
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

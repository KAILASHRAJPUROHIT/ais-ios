import SwiftUI

/// JARVIS controls: presence, voice, screen, agent, and the voice profile.
///
/// Every response body here is rendered from raw JSON on purpose. The
/// request/response schemas in app/api/jarvis.py were not verified when this
/// screen was written, so no field names are assumed -- the payload is shown
/// exactly as the host returned it, sorted for stability.
struct JarvisView: View {
    @State private var status = LoadState<[String: Any]>.idle
    @State private var presence = LoadState<[String: Any]>.idle
    @State private var profile = LoadState<[String: Any]>.idle

    @State private var utterance = ""
    @State private var talkResult = LoadState<JarvisReply>.idle
    @State private var agentGoal = ""
    @State private var agentResult = LoadState<[String: Any]>.idle
    @State private var presenceState = "home"
    @State private var lastAction = LoadState<[String: Any]>.idle
    @State private var busy = false

    private let api = AisApi()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        statusCard
                        talkCard
                        presenceCard
                        voiceProfileCard
                        agentCard
                        lastActionCard
                    }
                    .padding(14)
                }
            }
            .navigationTitle("JARVIS")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { load() } label: { Image(systemName: "arrow.clockwise") }
                }
            }
            .task { load() }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel("STATUS \u{00B7} GET /jarvis/status")
                Spacer()
                StateBanner(state: status)
            }
            if case .loaded(let o) = status {
                KV(key: "payload", value: Self.render(o))
            } else {
                Text(status.detail).font(.caption2).foregroundColor(status.tint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var talkCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("TALK \u{00B7} POST /jarvis/talk")
            TextField("utterance", text: $utterance, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("SEND (REAL)") { talk(dryRun: false) }
                    .buttonStyle(.borderedProminent).tint(Theme.warn)
                Button("DRY RUN") { talk(dryRun: true) }
                    .buttonStyle(.bordered).tint(Theme.accent)
            }
            .disabled(utterance.isEmpty || busy)
            talkOutcome
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    @ViewBuilder
    private var talkOutcome: some View {
        switch talkResult {
        case .loaded(let r):
            VStack(alignment: .leading, spacing: 2) {
                StateBanner(state: talkResult)
                KV(key: "spoken_ack", value: r.spokenAck ?? "", mono: false)
                KV(key: "decision", value: r.decisionType ?? "")
                KV(key: "laya", value: r.latencyLayaMs.map { String(format: "%.2f ms", $0) } ?? "UNMEASURED")
                KV(key: "events", value: r.eventsPublished.map(String.init) ?? "UNMEASURED")
                if let t = r.traceId, !t.isEmpty {
                    NavigationLink {
                        ChainView(traceId: t, title: "TALK TRACE")
                    } label: {
                        Text("VIEW TRACE \u{2192}").font(.caption.weight(.semibold))
                    }
                }
            }
        case .unreachable, .rejected:
            Text(talkResult.detail).font(.caption2).foregroundColor(talkResult.tint)
        default: EmptyView()
        }
    }

    private var presenceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("PRESENCE \u{00B7} GET /jarvis/presence")
                Spacer()
                StateBanner(state: presence)
            }
            if case .loaded(let o) = presence {
                KV(key: "payload", value: Self.render(o))
            } else {
                Text(presence.detail).font(.caption2).foregroundColor(presence.tint)
            }
            HStack {
                TextField("state", text: $presenceState)
                    .textInputAutocapitalization(.never)
                    .textFieldStyle(.roundedBorder)
                Button("SET") { checkPresence() }
                    .buttonStyle(.bordered).tint(Theme.accent)
                    .disabled(presenceState.isEmpty || busy)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var voiceProfileCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("VOICE PROFILE \u{00B7} GET /jarvis/voice/profile")
                Spacer()
                StateBanner(state: profile)
            }
            if case .loaded(let o) = profile {
                KV(key: "payload", value: Self.render(o))
            } else {
                Text(profile.detail).font(.caption2).foregroundColor(profile.tint)
            }
            Button("CLEAR PROFILE") { clearProfile() }
                .buttonStyle(.bordered).tint(Theme.bad)
                .disabled(busy)
            Text("Clearing removes the enrolled speaker. Re-enrolment is required afterwards.")
                .font(.caption2).foregroundColor(Theme.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var agentCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("AGENT \u{00B7} POST /jarvis/agent/run")
            TextField("goal", text: $agentGoal, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)
            Button("RUN AGENT") { runAgent() }
                .buttonStyle(.bordered).tint(Theme.accent)
                .disabled(agentGoal.isEmpty || busy)
            if case .loaded(let o) = agentResult {
                KV(key: "result", value: Self.render(o))
            } else if case .unreachable = agentResult {
                Text(agentResult.detail).font(.caption2).foregroundColor(Theme.warn)
            } else if case .rejected = agentResult {
                Text(agentResult.detail).font(.caption2).foregroundColor(Theme.bad)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var lastActionCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel("LAST ACTION")
                Spacer()
                StateBanner(state: lastAction)
            }
            if case .loaded(let o) = lastAction {
                KV(key: "result", value: Self.render(o))
            } else if lastAction.detail != LoadState<[String: Any]>.idle.detail {
                Text(lastAction.detail).font(.caption2).foregroundColor(lastAction.tint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Actions

    private func load() {
        Task {
            async let a = fetchStatus()
            async let b = fetchPresence()
            async let c = fetchProfile()
            _ = await (a, b, c)
        }
    }

    private func fetchStatus() async {
        status = .loading
        do { status = .loaded(try await api.jarvisStatus()) }
        catch { status = stateFor(error) }
    }

    private func fetchPresence() async {
        presence = .loading
        do { presence = .loaded(try await api.presence()) }
        catch { presence = stateFor(error) }
    }

    private func fetchProfile() async {
        profile = .loading
        do { profile = .loaded(try await api.voiceProfile()) }
        catch { profile = stateFor(error) }
    }

    private func talk(dryRun: Bool) {
        busy = true
        talkResult = .loading
        Task {
            defer { busy = false }
            do { talkResult = .loaded(try await api.talk(utterance, dryRun: dryRun)) }
            catch { talkResult = stateFor(error) }
        }
    }

    private func checkPresence() {
        busy = true
        Task {
            defer { busy = false }
            do {
                lastAction = .loaded(try await api.checkPresence(presenceState))
                await fetchPresence()
            } catch {
                lastAction = stateFor(error)
            }
        }
    }

    private func clearProfile() {
        busy = true
        Task {
            defer { busy = false }
            do {
                lastAction = .loaded(try await api.clearVoiceProfile())
                await fetchProfile()
            } catch {
                lastAction = stateFor(error)
            }
        }
    }

    private func runAgent() {
        busy = true
        agentResult = .loading
        Task {
            defer { busy = false }
            do { agentResult = .loaded(try await api.runAgent(goal: agentGoal)) }
            catch { agentResult = stateFor(error) }
        }
    }

    /// Sorted, stable rendering of an untyped JSON object.
    static func render(_ o: [String: Any]) -> String {
        EventCard.render(o)
    }
}

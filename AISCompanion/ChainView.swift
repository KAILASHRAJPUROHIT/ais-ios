import SwiftUI

/// Wrapper so a bare trace id can drive `.sheet(item:)`.
/// Deliberately NOT `extension String: Identifiable` -- a retroactive
/// conformance on a stdlib type is a real collision risk in a shared module.
struct TraceRef: Identifiable, Equatable {
    let id: String
    init(_ id: String) { self.id = id }
}

/// Causal chain for one trace.
///
/// An unknown trace is an EMPTY state, not a failure: the host answered
/// successfully with no events. A 404 from the learning-loop evidence route
/// is a rejection and is shown as such, because it means "no such loop".
struct ChainView: View {
    let traceId: String
    let title: String

    @Environment(\.dismiss) private var dismiss
    @State private var state = LoadState<[EventEnvelope]>.idle
    @State private var useLearningLoopRoute = false
    private let api = AisApi()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        // Header drawn inline rather than via .toolbar.
                        // toolbar(content:) was ambiguous here, and a sheet
                        // does not need navigation chrome.
                        HStack {
                            Text(title)
                                .font(.caption.weight(.bold))
                                .foregroundColor(Theme.accent)
                            Spacer()
                            StateBanner(state: state)
                            Button { load() } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            Button("CLOSE") { dismiss() }
                                .font(.caption.weight(.semibold))
                        }
                        Picker("route", selection: $useLearningLoopRoute) {
                            Text("events/chain").tag(false)
                            Text("learning-loop").tag(true)
                        }
                        .pickerStyle(.segmented)
                        KV(key: "trace_id", value: traceId)

                        switch state {
                        case .loaded(let list):
                            ForEach(Array(list.enumerated()), id: \.offset) { i, e in
                                EventCard(index: i, event: e)
                            }
                        case .empty:
                            Text(state.detail).font(.caption2).foregroundColor(Theme.dim)
                        case .unreachable, .rejected:
                            Text(state.detail).font(.caption2).foregroundColor(state.tint)
                        case .loading:
                            ProgressView()
                        case .idle:
                            Text("Not requested yet.").font(.caption2).foregroundColor(Theme.dim)
                        }
                    }
                    .padding(14)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .task { load() }
            // Single-parameter onChange: the two-parameter form is iOS 17,
            // but this target deploys to iOS 16.0.
            .onChange(of: useLearningLoopRoute) { _ in load() }
        }
    }

    private func load() {
        state = .loading
        Task {
            do {
                let list = useLearningLoopRoute
                    ? try await api.learningLoopEvidence(traceId: traceId)
                    : try await api.chain(traceId: traceId)
                state = list.isEmpty ? .empty : .loaded(list)
            } catch {
                state = stateFor(error)
            }
        }
    }
}

/// One event in a chain, with its provenance badge.
struct EventCard: View {
    let index: Int
    let event: EventEnvelope

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(String(format: "%02d", index + 1))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.accent)
                Text(event.eventType ?? "UNTYPED")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.text)
                Spacer()
                Text(Truth.badgeText(event))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Truth.badgeColor(event))
            }
            KV(key: "event_id", value: event.eventId ?? "")
            KV(key: "source", value: event.source ?? "")
            KV(key: "modality", value: event.temporalModality ?? "")
            if let p = event.payload, !p.isEmpty {
                DisclosureGroup("payload") {
                    Text(Self.render(p))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Theme.dim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption2)
                .foregroundColor(Theme.dim)
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// Stable, sorted rendering so the same payload always displays the same
    /// way. A dictionary has no inherent order, so sorting avoids the UI
    /// reshuffling between refreshes.
    static func render(_ dict: [String: Any]) -> String {
        dict.keys.sorted().map { k in
            let v = dict[k] ?? ""
            return "\(k): \(v)"
        }.joined(separator: "\n")
    }
}

import SwiftUI

struct EventsView: View {
    @State private var events: [EventEnvelope] = []
    @State private var streamState: StreamLabel = .connecting
    private let api = AisApi()

    enum StreamLabel { case connecting, live, disconnected
        var text: String {
            switch self {
            case .connecting: return "STREAM: CONNECTING"
            case .live: return "STREAM: LIVE"
            case .disconnected: return "STREAM: DISCONNECTED"
            }
        }
        var color: Color {
            switch self {
            case .live: return Theme.good
            case .connecting: return Theme.warn
            case .disconnected: return Theme.bad
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(streamState.text)
                            .font(.caption)
                            .foregroundColor(streamState.color)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card()

                        if events.isEmpty {
                            Text(streamState == .disconnected
                                 ? "Stream disconnected. This is NOT an indication the system is idle."
                                 : "No events received yet.")
                                .font(.caption)
                                .foregroundColor(Theme.dim)
                                .card()
                        } else {
                            ForEach(events) { ev in
                                eventRow(ev)
                            }
                        }
                    }
                    .padding(14)
                }
            }
            .navigationTitle("EVENTS")
            .task { await stream() }
        }
    }

    private func eventRow(_ ev: EventEnvelope) -> some View {
        let b = Truth.badge(for: ev)
        return VStack(alignment: .leading, spacing: 3) {
            Text(ev.eventType ?? "unknown")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Theme.accent)
            Text((ev.source ?? "?") + (ev.traceId.map { " \u{00B7} \($0)" } ?? ""))
                .font(.caption2).foregroundColor(Theme.dim)
            Text(String(describing: ev.payload ?? [:]).prefix(220))
                .font(.system(size: 11)).foregroundColor(Theme.text)
            // Truth badge: provenance decides, never the event type alone.
            Text(b.label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(b == .verifiedLive ? Theme.good : Theme.warn)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Theme.bg).clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .card()
    }

    private func stream() async {
        if api.authToken.isEmpty {
            streamState = .disconnected
            return
        }
        for await s in api.eventStream() {
            switch s {
            case .connecting: streamState = .connecting
            case .disconnected: streamState = .disconnected
            case .event(let e):
                streamState = .live
                events.insert(e, at: 0)
                if events.count > 100 { events.removeLast() }
            }
        }
    }
}

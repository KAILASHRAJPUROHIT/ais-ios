import SwiftUI

struct TalkView: View {
    @State private var utterance = ""
    @State private var dryRun = true
    @State private var reply: String = "—"
    @State private var meta: String = ""
    @State private var reachable: String = "CHECKING…"
    @State private var busy = false
    @State private var micNote: String?

    private let api = AisApi()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        banner(reachable, color: reachableColor)

                        TextField("Type a command or question…", text: $utterance, axis: .vertical)
                            .lineLimit(2...4)
                            .textFieldStyle(.plain)
                            .card()

                        HStack {
                            Button {
                                Task { await send() }
                            } label: {
                                Label(busy ? "SENDING" : "SEND",
                                      systemImage: "arrow.up.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.accent)
                            .disabled(busy || utterance.trimmingCharacters(in: .whitespaces).isEmpty)

                            Button {
                                micNote = "The AIS host does not yet expose a transcription " +
                                          "endpoint. Type the utterance to send it."
                            } label: {
                                Label("VOICE", systemImage: "mic.circle")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(Theme.accent)
                        }

                        Toggle("Dry run (no real command executed)", isOn: $dryRun)
                            .font(.caption)
                            .foregroundColor(Theme.text)
                            .tint(Theme.accent)

                        Text("RESULT").font(.caption2).foregroundColor(Theme.dim)
                        Text(reply)
                            .font(.system(size: 14))
                            .foregroundColor(Theme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card()

                        Text(meta)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Theme.dim)

                        if let micNote {
                            Text(micNote)
                                .font(.caption)
                                .foregroundColor(Theme.warn)
                                .card()
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("TALK")
            .toolbarBackground(Theme.surface, for: .navigationBar)
            .task { await probe() }
        }
    }

    private var reachableColor: Color {
        reachable.hasPrefix("AIS REACHABLE") ? Theme.good : Theme.bad
    }

    private func banner(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
    }

    private func probe() async {
        do {
            _ = try await api.jarvisStatus()
            reachable = "AIS REACHABLE"
        } catch let e as AisApi.ApiError {
            // Unreachable is neither healthy nor failed.
            reachable = e.isTransportFailure ? "AIS UNREACHABLE" : "AIS ERROR: \(e.localizedDescription)"
        } catch {
            reachable = "AIS ERROR"
        }
    }

    private func send() async {
        let text = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        busy = true
        reply = "SENDING…"
        meta = ""
        defer { busy = false }

        do {
            let r = try await api.talk(text, dryRun: dryRun)
            reply = r.spokenAck?.isEmpty == false ? r.spokenAck! : "(no spoken acknowledgement)"
            let latency = r.latencyLayaMs.map { String(format: "%.2f", $0) } ?? "—"
            let mode = dryRun ? "DRY RUN (not executed)" : "EXECUTED"
            var m = "\(mode) · \(r.decisionType ?? "UNKNOWN") · Laya \(latency)ms\n"
            m += "trace: \(r.traceId ?? "none") · events: \(r.eventsPublished ?? 0)"
            if dryRun {
                m += "\nNote: backend labels dry-run events REAL_EXECUTION (known defect)."
            }
            meta = m
        } catch let e as AisApi.ApiError {
            reply = e.localizedDescription
            meta = "trace: none — no event was emitted"
        } catch {
            reply = "Something went wrong."
            meta = ""
        }
    }
}

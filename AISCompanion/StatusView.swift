import SwiftUI

struct StatusView: View {
    @State private var status: String = "LOADING"
    @State private var statusColor: Color = Theme.text
    @State private var provenance: String = ""
    @State private var metrics: String = "\u{2014}"
    @State private var jarvis: String = "\u{2014}"
    private let api = AisApi()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("SYSTEM")
                                .font(.caption2).foregroundColor(Theme.dim)
                            Text(status)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(statusColor)
                            Text(provenance)
                                .font(.system(size: 11)).foregroundColor(Theme.dim)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()

                        VStack(alignment: .leading, spacing: 6) {
                            Text("METRICS (as reported by backend)")
                                .font(.caption2).foregroundColor(Theme.dim)
                            Text(metrics)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(Theme.text)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()

                        VStack(alignment: .leading, spacing: 6) {
                            Text("JARVIS")
                                .font(.caption2).foregroundColor(Theme.dim)
                            Text(jarvis)
                                .font(.system(size: 12)).foregroundColor(Theme.text)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()

                        Button("REFRESH") { load() }
                            .buttonStyle(.borderedProminent).tint(Theme.accent)
                    }
                    .padding(14)
                }
            }
            .navigationTitle("STATUS")
            .task { load() }
        }
    }

    private func load() {
        status = "LOADING"; Task { await fetch() }
    }

    private func fetch() async {
        do {
            let h = try await api.health()
            status = (h.statusLabel ?? h.status ?? "UNKNOWN").replacingOccurrences(of: "_", with: " ")
            statusColor = (h.status == "HEALTHY") ? Theme.good : Theme.warn
            provenance = "status=\(h.status ?? "?") \u{00B7} provenance=\(h.provenance ?? "?")"
            // A NULL average is UNMEASURED, never 0.0.
            func orUnmeasured(_ v: Double?) -> String {
                v.map { "\($0)" } ?? "UNMEASURED"
            }
            metrics = """
            models registered : \(h.models?.registered.map(String.init) ?? "\u{2014}")
            providers healthy : \(h.providers?.healthy.map(String.init) ?? "\u{2014}")
            test pass rate    : \(h.testing?.passRate.map { "\($0) %" } ?? "UNMEASURED")
            laya decisions    : \(h.laya?.totalDecisions.map(String.init) ?? "\u{2014}")
            laya mean latency : \(orUnmeasured(h.laya?.meanLatencyMs))
            """
        } catch let e as AisApi.ApiError {
            // Unreachable is neither healthy nor failed.
            status = e.isTransportFailure ? "UNREACHABLE" : "ERROR: \(e.localizedDescription)"
            statusColor = Theme.bad
            provenance = "No health data. This is not a pass or a fail \u{2014} AIS did not report its state."
            metrics = "\u{2014}"
        } catch {
            status = "ERROR"; statusColor = Theme.bad
        }

        do {
            let o = try await api.jarvisStatus()
            let caps = (o["capabilities"] as? [String] ?? []).joined(separator: "\n  ")
            jarvis = """
            reported status : \(o["status"] as? String ?? "\u{2014}")
            decision layer  : \(o["decision_layer"] as? String ?? "\u{2014}")
            model           : \(o["default_model"] as? String ?? "\u{2014}")
            spend           : \(o["spend_rate"] as? String ?? "\u{2014}")
            capabilities    : \(caps)

            Note: /jarvis/status returns a static 'ONLINE' string. It is a
            report, not a live probe.
            """
        } catch let e as AisApi.ApiError {
            jarvis = e.isTransportFailure
                ? "JARVIS status unavailable \u{2014} AIS host unreachable."
                : "JARVIS status error: \(e.localizedDescription)"
        } catch {
            jarvis = "JARVIS status unavailable."
        }
    }
}

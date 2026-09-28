import SwiftUI

/// Laya Decision Fabric + Learning Loop.
///
/// These two subsystems had no interface at all before this screen; the API
/// layer covered the routes but nothing in the app could reach them.
struct LearnView: View {
    @State private var decisions = LoadState<[LayaDecisionRecord]>.idle
    @State private var lessons = LoadState<[Lesson]>.idle
    @State private var lastRun = LoadState<LearningLoopRun>.idle

    @State private var decisionType = ""
    @State private var contextJSON = "{\n  \"text\": \"probe\"\n}"
    @State private var evalResult = LoadState<LayaDecisionResponse>.idle
    @State private var simulateOffline = false
    @State private var running = false
    @State private var evidenceFor: TraceRef?

    private let api = AisApi()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        evaluateCard
                        decisionsCard
                        learningCard
                        lessonsCard
                    }
                    .padding(14)
                }
            }
            .navigationTitle("LEARN")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { loadAll() } label: { Image(systemName: "arrow.clockwise") }
                }
            }
            .task { loadAll() }
            .sheet(item: $evidenceFor) { ref in
                ChainView(traceId: ref.id, title: "LOOP EVIDENCE")
            }
        }
    }

    private var evaluateCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("LAYA \u{00B7} POST /laya/evaluate")

            TextField("decision_type", text: $decisionType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

            TextField("context JSON", text: $contextJSON, axis: .vertical)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(2...6)
                .textFieldStyle(.roundedBorder)

            Toggle("Simulate offline (Constitution Rule #2)", isOn: $simulateOffline)
                .font(.caption)
                .foregroundColor(Theme.text)

            Button("EVALUATE") { runEvaluate() }
                .buttonStyle(.borderedProminent).tint(Theme.accent)
                .disabled(decisionType.isEmpty || running)

            switch evalResult {
            case .loaded(let d):
                VStack(alignment: .leading, spacing: 4) {
                    StateBanner(state: evalResult)
                    KV(key: "decision_id", value: d.decisionId ?? "")
                    KV(key: "checkpoint", value: d.checkpoint ?? "")
                    KV(key: "latency", value: d.decisionTimeMs.map { String(format: "%.2f ms", $0) } ?? "UNMEASURED")
                    KV(key: "applicability", value: d.applicability ?? "")
                    KV(key: "is_fallback", value: d.isFallback.map { $0 ? "true" : "false" } ?? "\u{2014}",
                       tint: (d.isFallback ?? false) ? Theme.warn : Theme.text)
                    if let r = d.fallbackReason { KV(key: "fallback_reason", value: r, tint: Theme.warn) }
                    if let q = d.questions, !q.isEmpty {
                        ForEach(q.keys.sorted(), id: \.self) { k in
                            if let qq = q[k] { KV(key: k, value: describe(qq)) }
                        }
                    }
                }
                .padding(.top, 4)
            case .unreachable, .rejected:
                VStack(alignment: .leading, spacing: 2) {
                    StateBanner(state: evalResult)
                    Text(evalResult.detail).font(.caption2).foregroundColor(Theme.dim)
                }
            default: EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var decisionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("DECISION LOG \u{00B7} GET /laya/decisions")
                Spacer()
                StateBanner(state: decisions)
            }
            if case .loaded(let list) = decisions {
                if list.isEmpty {
                    Text(LoadState<[LayaDecisionRecord]>.empty.detail)
                        .font(.caption2).foregroundColor(Theme.dim)
                } else {
                    ForEach(list.prefix(20)) { d in
                        VStack(alignment: .leading, spacing: 2) {
                            KV(key: "type", value: d.decisionType ?? "")
                            KV(key: "latency", value: d.decisionTimeMs.map { String(format: "%.2f ms", $0) } ?? "UNMEASURED")
                            if (d.isFallback ?? 0) != 0 {
                                KV(key: "fallback", value: d.fallbackReason ?? "true", tint: Theme.warn)
                            }
                            KV(key: "created", value: d.createdAt ?? "")
                        }
                        .padding(8)
                        .background(Color.black.opacity(0.25))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            } else if case .unreachable = decisions {
                Text(decisions.detail).font(.caption2).foregroundColor(Theme.warn)
            } else if case .rejected = decisions {
                Text(decisions.detail).font(.caption2).foregroundColor(Theme.bad)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var learningCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("LEARNING LOOP \u{00B7} POST /learning-loop/run")
            Text("Runs the 7-step cycle: failure \u{2192} diagnosis \u{2192} lesson \u{2192} Laya assessment \u{2192} validation \u{2192} gate \u{2192} record.")
                .font(.caption2).foregroundColor(Theme.dim)
            Button("RUN LOOP") { runLoop() }
                .buttonStyle(.borderedProminent).tint(Theme.accent)
                .disabled(running)
            switch lastRun {
            case .loaded(let r):
                VStack(alignment: .leading, spacing: 2) {
                    StateBanner(state: lastRun)
                    KV(key: "loop_id", value: r.loopId ?? "")
                    KV(key: "trace_id", value: r.traceId ?? "")
                    KV(key: "lesson_status", value: r.lessonStatus ?? "")
                    KV(key: "prevention", value: r.preventionWorked.map { $0 ? "worked" : "did not work" } ?? "UNMEASURED",
                       tint: (r.preventionWorked ?? false) ? Theme.good : Theme.warn)
                    KV(key: "events", value: r.eventCount.map(String.init) ?? "UNMEASURED")
                    if let t = r.traceId, !t.isEmpty {
                        Button("VIEW EVIDENCE CHAIN") { evidenceFor = TraceRef(t) }
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Theme.accent)
                    }
                }
            case .unreachable, .rejected:
                VStack(alignment: .leading, spacing: 2) {
                    StateBanner(state: lastRun)
                    Text(lastRun.detail).font(.caption2).foregroundColor(Theme.dim)
                }
            default: EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var lessonsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("VALIDATED LESSONS \u{00B7} GET /learning-loop/lessons")
                Spacer()
                StateBanner(state: lessons)
            }
            if case .loaded(let list) = lessons {
                if list.isEmpty {
                    Text(LoadState<[Lesson]>.empty.detail)
                        .font(.caption2).foregroundColor(Theme.dim)
                } else {
                    ForEach(list) { l in
                        VStack(alignment: .leading, spacing: 2) {
                            KV(key: "condition", value: l.lessonCondition ?? "", mono: false)
                            KV(key: "prevention", value: l.preventionAction ?? "", mono: false)
                            KV(key: "confidence", value: l.confidence.map { String(format: "%.3f", $0) } ?? "UNMEASURED")
                            KV(key: "validated", value: l.createdAt ?? "")
                        }
                        .padding(8)
                        .background(Color.black.opacity(0.25))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            } else if case .unreachable = lessons {
                Text(lessons.detail).font(.caption2).foregroundColor(Theme.warn)
            } else if case .rejected = lessons {
                Text(lessons.detail).font(.caption2).foregroundColor(Theme.bad)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Actions

    private func loadAll() {
        Task {
            async let d = fetchDecisions()
            async let l = fetchLessons()
            _ = await (d, l)
        }
    }

    private func fetchDecisions() async {
        decisions = .loading
        do {
            let list = try await api.layaDecisions(limit: 50)
            // A successful response with no rows is an EMPTY state, not a
            // failure and not an error.
            decisions = list.isEmpty ? .empty : .loaded(list)
        } catch {
            decisions = stateFor(error)
        }
    }

    private func fetchLessons() async {
        lessons = .loading
        do {
            let list = try await api.lessons(limit: 50)
            lessons = list.isEmpty ? .empty : .loaded(list)
        } catch {
            lessons = stateFor(error)
        }
    }

    private func runEvaluate() {
        running = true
        evalResult = .loading
        Task {
            defer { running = false }
            guard let data = contextJSON.data(using: .utf8),
                  let ctx = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                evalResult = .rejected(0, "Context is not a valid JSON object.")
                return
            }
            do {
                evalResult = .loaded(try await api.evaluate(
                    decisionType: decisionType, context: ctx, simulateOffline: simulateOffline))
                await fetchDecisions()
            } catch {
                evalResult = stateFor(error)
            }
        }
    }

    private func runLoop() {
        running = true
        lastRun = .loading
        Task {
            defer { running = false }
            do {
                lastRun = .loaded(try await api.runLearningLoop())
                await fetchLessons()
            } catch {
                lastRun = stateFor(error)
            }
        }
    }

    private func describe(_ q: LayaQuestion) -> String {
        if let c = q.choice { return "choice: \(c.selected ?? "\u{2014}")" }
        if let s = q.score { return "score: \(String(format: "%.4f", s.expected ?? 0))" }
        if let n = q.noul { return "noul: p(true)=\(String(format: "%.4f", n.probabilityTrue ?? 0))" }
        return q.type ?? "UNRECOGNIZED"
    }
}

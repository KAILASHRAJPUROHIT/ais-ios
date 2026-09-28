import Foundation

/// HTTP client for the AIS backend.
///
/// SECURITY: the backend REQUIRES a bearer token on every protected route.
/// `POST /jarvis/talk` can execute host commands, so an empty token yields
/// 401, not anonymous access. The token is provisioned per device at setup
/// and stored in the iOS Keychain via SecureStore -- it is never compiled
/// into this binary.
///
/// TRUTH DISCIPLINE: a transport failure and a server rejection are distinct
/// cases. An unreachable host is NOT "failed" and NOT "healthy" - it is
/// UNREACHABLE, which the UI renders differently.
struct AisApi {
    var baseURL: URL
    var authToken: String = ""

    init(baseURL: URL? = nil, authToken: String = "") {
        if let baseURL {
            self.baseURL = baseURL
        } else if let raw = UserDefaults.standard.string(forKey: "aisBaseURL"),
                  let u = URL(string: raw) {
            self.baseURL = u
        } else {
            self.baseURL = URL(string: "http://127.0.0.1:8000")!
        }
        // Read the token from the Keychain, not UserDefaults. A value found
        // in the legacy insecure location is used only so an existing install
        // does not silently lose its token; SettingsContent migrates it to
        // the Keychain on save.
        let secure = SecureStore().readToken()
        if !secure.isEmpty {
            self.authToken = secure
        } else if let legacy = UserDefaults.standard.string(forKey: "aisAuthToken"),
                  !legacy.isEmpty {
            self.authToken = legacy
        } else {
            self.authToken = authToken
        }
    }

    enum ApiError: Error, LocalizedError {
        case unreachable(String)
        case rejected(Int, String)
        case malformed

        var errorDescription: String? {
            switch self {
            case .unreachable(let m): return "Cannot reach AIS: \(m). Nothing was executed."
            case .rejected(let code, _): return "AIS returned HTTP \(code)."
            case .malformed: return "AIS returned an unreadable response."
            }
        }

        var isTransportFailure: Bool {
            if case .unreachable = self { return true }
            return false
        }
    }

    /// Perform a request.
    ///
    /// NOTE: this was previously a blocking `URLSession.dataTask` bridged with
    /// a `DispatchSemaphore` and a shared `var result` mutated from an escaping
    /// closure. That is a data race, and newer Swift compilers reject the
    /// "mutation of captured var in concurrently-executing code" pattern. It
    /// also blocked a thread for up to 40s. Plain async/await is correct here.
    private func request(_ path: String, method: String = "GET",
                         body: [String: Any]? = nil) async throws -> Data {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.timeoutInterval = method == "GET" ? 12 : 30
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        if !authToken.isEmpty {
            req.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            // A transport failure is distinct from a server rejection: the UI
            // renders UNREACHABLE differently from an HTTP error.
            throw ApiError.unreachable(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw ApiError.malformed }
        guard (200..<300).contains(http.statusCode) else {
            // `data` here is a non-optional `Data` (URLSession.data(for:) always
            // returns Data, possibly empty). `flatMap` on a non-optional value
            // tried to apply the String(data:encoding:) overload element-wise,
            // which failed to type-check.
            let text = data.isEmpty ? "" : String(decoding: data, as: UTF8.self)
            throw ApiError.rejected(http.statusCode, String(text.prefix(200)))
        }
        return data
    }


    // MARK: - Health / Status

    func health() async throws -> Health {
        let data = try await request("health")
        return try JSONDecoder().decode(Health.self, from: data)
    }

    func jarvisStatus() async throws -> [String: Any] {
        let data = try await request("jarvis/status")
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ApiError.malformed
        }
        return obj
    }

    // MARK: - Events

    func latestEvent() async throws -> EventEnvelope? {
        let data = try await request("events/latest")
        if data.isEmpty { return nil }  // empty body is a valid empty state
        return try JSONDecoder().decode(EventEnvelope.self, from: data)
    }

    // MARK: - JARVIS

    /// `dryRun` is surfaced explicitly because the backend currently stamps
    /// provenance=REAL_EXECUTION on the event chain even for dry runs.
    func talk(_ utterance: String, dryRun: Bool) async throws -> JarvisReply {
        let data = try await request("jarvis/talk", method: "POST",
                                     body: ["utterance": utterance, "dry_run": dryRun])
        return try JSONDecoder().decode(JarvisReply.self, from: data)
    }

    func createTask(_ title: String) async throws {
        _ = try await request("tasks", method: "POST",
                              body: ["title": title, "description": ""])
    }

    // MARK: - Events (full parity)

    func publishEvent(type: String, payload: [String: Any],
                      source: String = "ais.companion.ios") async throws -> EventEnvelope? {
        let data = try await request("events", method: "POST",
                                     body: ["event_type": type, "source": source,
                                            "payload": payload])
        return try? JSONDecoder().decode(EventEnvelope.self, from: data)
    }

    func events(limit: Int = 100, eventType: String? = nil) async throws -> [EventEnvelope] {
        var q = [URLQueryItem(name: "limit", value: String(limit))]
        if let eventType { q.append(URLQueryItem(name: "event_type", value: eventType)) }
        let data = try await request("events?" + Self.query(q))
        return try JSONDecoder().decode([EventEnvelope].self, from: data)
    }

    /// Causal chain for one trace. An unknown trace yields an empty list, not
    /// an error, and must not be rendered as a failure.
    func chain(traceId: String) async throws -> [EventEnvelope] {
        let data = try await request("events/chain/\(traceId)")
        return try JSONDecoder().decode([EventEnvelope].self, from: data)
    }

    func taskLifecycleDemo() async throws -> [String: Any] {
        let data = try await request("events/task-lifecycle-demo", method: "POST", body: [:])
        return try Self.object(from: data)
    }

    // MARK: - Tasks (full parity)

    func tasks() async throws -> [String: Any] {
        let data = try await request("tasks")
        return try Self.object(from: data)
    }

    func updateTask(_ taskId: String, state: String) async throws -> [String: Any] {
        let data = try await request("tasks/\(taskId)", method: "PATCH", body: ["state": state])
        return try Self.object(from: data)
    }

    // MARK: - JARVIS (full parity)
    //
    // These bodies are intentionally raw JSON. Their schemas were not
    // verified against app/api/jarvis.py when this was written, and guessing
    // field names would render plausible-but-false data. Type them only after
    // reading that file.

    func voice(text: String) async throws -> [String: Any] {
        try Self.object(from: await request("jarvis/voice", method: "POST", body: ["text": text]))
    }

    func screen(action: String, target: String? = nil) async throws -> [String: Any] {
        var b: [String: Any] = ["action": action]
        if let target { b["target"] = target }
        return try Self.object(from: await request("jarvis/screen", method: "POST", body: b))
    }

    func presence() async throws -> [String: Any] {
        try Self.object(from: await request("jarvis/presence"))
    }

    func checkPresence(_ state: String) async throws -> [String: Any] {
        try Self.object(from: await request("jarvis/presence/check", method: "POST", body: ["state": state]))
    }

    func runAgent(goal: String, maxSteps: Int = 10) async throws -> [String: Any] {
        try Self.object(from: await request("jarvis/agent/run", method: "POST",
                                            body: ["goal": goal, "max_steps": maxSteps]))
    }

    func voiceProfile() async throws -> [String: Any] {
        try Self.object(from: await request("jarvis/voice/profile"))
    }

    func clearVoiceProfile() async throws -> [String: Any] {
        try Self.object(from: await request("jarvis/voice/profile/clear", method: "POST", body: [:]))
    }

    // MARK: - Laya

    func evaluate(decisionType: String, context: [String: Any],
                  checkpoint: String = "default",
                  simulateOffline: Bool = false) async throws -> LayaDecisionResponse {
        let data = try await request("laya/evaluate?simulate_offline=\(simulateOffline)",
                                     method: "POST",
                                     body: ["decision_type": decisionType,
                                            "context": context,
                                            "checkpoint": checkpoint])
        return try JSONDecoder().decode(LayaDecisionResponse.self, from: data)
    }

    func layaDecisions(limit: Int = 50, decisionType: String? = nil) async throws -> [LayaDecisionRecord] {
        var q = [URLQueryItem(name: "limit", value: String(limit))]
        if let decisionType { q.append(URLQueryItem(name: "decision_type", value: decisionType)) }
        let data = try await request("laya/decisions?" + Self.query(q))
        return try JSONDecoder().decode([LayaDecisionRecord].self, from: data)
    }

    // MARK: - Learning loop
    //
    // Hyphenated prefix, per backend/app/api/learning_loop.py.

    func runLearningLoop(taskAId: String? = nil, taskBId: String? = nil,
                         failureOutput: String? = nil, successOutputB: String? = nil) async throws -> LearningLoopRun {
        var q: [URLQueryItem] = []
        if let taskAId { q.append(URLQueryItem(name: "task_a_id", value: taskAId)) }
        if let taskBId { q.append(URLQueryItem(name: "task_b_id", value: taskBId)) }
        if let failureOutput { q.append(URLQueryItem(name: "failure_output", value: failureOutput)) }
        if let successOutputB { q.append(URLQueryItem(name: "success_output_b", value: successOutputB)) }
        let suffix = q.isEmpty ? "" : "?" + Self.query(q)
        let data = try await request("learning-loop/run" + suffix, method: "POST", body: [:])
        return try JSONDecoder().decode(LearningLoopRun.self, from: data)
    }

    func lessons(limit: Int = 50) async throws -> [Lesson] {
        let data = try await request("learning-loop/lessons?limit=\(limit)")
        return try JSONDecoder().decode([Lesson].self, from: data)
    }

    /// 404 here means "no such learning loop", which is a different fact from
    /// "host unreachable" and is surfaced as such.
    func learningLoopEvidence(traceId: String) async throws -> [EventEnvelope] {
        let data = try await request("learning-loop/evidence/\(traceId)")
        return try JSONDecoder().decode([EventEnvelope].self, from: data)
    }

    // MARK: - Helpers

    private static func object(from data: Data) throws -> [String: Any] {
        guard let o = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ApiError.malformed
        }
        return o
    }

    private static func query(_ items: [URLQueryItem]) -> String {
        var c = URLComponents()
        c.queryItems = items
        return c.percentEncodedQuery ?? ""
    }

    // MARK: - SSE

    enum StreamEvent {
        case connecting
        case event(EventEnvelope)
        case disconnected
    }

    /// Live event stream. Reconnects with exponential backoff.
    /// A dropped stream is surfaced as `.disconnected`, never as "no events".
    func eventStream() -> AsyncStream<StreamEvent> {
        AsyncStream { continuation in
            let task = Task {
                var attempt = 0
                while !Task.isCancelled {
                    continuation.yield(.connecting)
                    do {
                        try await consumeSSE { continuation.yield($0) }
                        attempt = 0
                    } catch {
                        continuation.yield(.disconnected)
                    }
                    if Task.isCancelled { break }
                    let backoff = min(pow(2.0, Double(attempt)), 30)
                    attempt += 1
                    try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                }
                continuation.yield(.disconnected)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func consumeSSE(_ emit: @escaping (StreamEvent) -> Void) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent("events/stream"))
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if !authToken.isEmpty {
            req.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        req.timeoutInterval = .infinity

        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw ApiError.rejected(0, "stream rejected")
        }

        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let raw = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            let data = Data(raw.utf8)
            if let evt = try? JSONDecoder().decode(EventEnvelope.self, from: data) {
                emit(.event(evt))
            }
        }
    }
}

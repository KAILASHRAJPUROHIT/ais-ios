import Foundation

/// HTTP client for the AIS backend.
///
/// SECURITY: the backend currently has NO authentication and
/// `POST /jarvis/talk` can execute Windows commands on the host
/// (LOCK_PC / SLEEP_PC). Keep `baseURL` on a LAN address.
/// Set `authToken` only once the backend enforces it.
///
/// TRUTH DISCIPLINE: a transport failure and a server rejection are distinct
/// cases. An unreachable host is NOT "failed" and NOT "healthy" — it is
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
        if let stored = UserDefaults.standard.string(forKey: "aisAuthToken") {
            self.authToken = stored.isEmpty ? authToken : stored
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

    private func request(_ path: String, method: String = "GET",
                         body: [String: Any]? = nil) throws -> Data {
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

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Data, ApiError> = .failure(.unreachable("no response"))

        URLSession.shared.dataTask(with: req) { data, response, error in
            defer { semaphore.signal() }
            if let error { result = .failure(.unreachable(error.localizedDescription)); return }
            guard let http = response as? HTTPURLResponse else {
                result = .failure(.malformed); return
            }
            guard (200..<300).contains(http.statusCode) else {
                let b = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                result = .failure(.rejected(http.statusCode, String(b.prefix(200)))); return
            }
            result = .success(data ?? Data())
        }.resume()

        _ = semaphore.wait(timeout: .now() + 40)
        return try result.get()
    }


    // MARK: - Health / Status

    func health() async throws -> Health {
        let data = try await perform { try request("health") }
        return try JSONDecoder().decode(Health.self, from: data)
    }

    func jarvisStatus() async throws -> [String: Any] {
        let data = try await perform { try request("jarvis/status") }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ApiError.malformed
        }
        return obj
    }

    // MARK: - Events

    func latestEvent() async throws -> EventEnvelope? {
        let data = try await perform { try request("events/latest") }
        if data.isEmpty { return nil }  // empty body is a valid empty state
        return try JSONDecoder().decode(EventEnvelope.self, from: data)
    }

    // MARK: - JARVIS

    /// `dryRun` is surfaced explicitly because the backend currently stamps
    /// provenance=REAL_EXECUTION on the event chain even for dry runs.
    func talk(_ utterance: String, dryRun: Bool) async throws -> JarvisReply {
        let data = try await perform {
            try request("jarvis/talk", method: "POST",
                        body: ["utterance": utterance, "dry_run": dryRun])
        }
        return try JSONDecoder().decode(JarvisReply.self, from: data)
    }

    func createTask(_ title: String) async throws {
        _ = try await perform {
            try request("tasks", method: "POST",
                        body: ["title": title, "description": ""])
        }
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
            guard let line, line.hasPrefix("data:") else { continue }
            let raw = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let data = raw.data(using: .utf8) else { continue }
            if let evt = try? JSONDecoder().decode(EventEnvelope.self, from: data) {
                emit(.event(evt))
            }
        }
    }

    private func perform(_ block: () throws -> Data) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do { cont.resume(returning: try block()) }
                catch let e as ApiError { cont.resume(throwing: e) }
                catch { cont.resume(throwing: ApiError.unreachable(error.localizedDescription)) }
            }
        }
    }
}

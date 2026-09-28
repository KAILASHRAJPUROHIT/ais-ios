import Foundation

/// A canonical AIS event, as returned by /events and /events/stream.
struct EventEnvelope: Decodable, Identifiable {
    let eventId: String?
    let traceId: String?
    let parentEventId: String?
    let eventType: String?
    let source: String?
    let temporalModality: String?
    let payload: [String: Any]?

    var id: String { eventId ?? UUID().uuidString }

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case traceId = "trace_id"
        case parentEventId = "parent_event_id"
        case eventType = "event_type"
        case source
        case temporalModality = "temporal_modality"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        eventId = try? c.decode(String.self, forKey: .eventId)
        traceId = try? c.decode(String.self, forKey: .traceId)
        parentEventId = try? c.decode(String.self, forKey: .parentEventId)
        eventType = try? c.decode(String.self, forKey: .eventType)
        source = try? c.decode(String.self, forKey: .source)
        temporalModality = try? c.decode(String.self, forKey: .temporalModality)

        // Payload is free-form. Decode it as raw JSON so Truth can read
        // `provenance` without knowing the concrete payload shape.
        if let raw = try? c.decode(AnyCodable.self, forKey: .payload) {
            payload = raw.value as? [String: Any]
        } else {
            payload = nil
        }
    }
}

/// Minimal helper to decode arbitrary JSON into Any.
struct AnyCodable: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let b = try? container.decode(Bool.self) {
            value = b
        } else if let i = try? container.decode(Int.self) {
            value = i
        } else if let d = try? container.decode(Double.self) {
            value = d
        } else if let s = try? container.decode(String.self) {
            value = s
        } else if let arr = try? container.decode([AnyCodable].self) {
            value = arr.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else {
            value = NSNull()
        }
    }
}

/// Reply from POST /jarvis/talk.
struct JarvisReply: Decodable {
    let traceId: String?
    let decisionType: String?
    let latencyLayaMs: Double?
    let spokenAck: String?
    let eventsPublished: Int?

    enum CodingKeys: String, CodingKey {
        case traceId = "trace_id"
        case decisionType = "decision_type"
        case latencyLayaMs = "latency_laya_ms"
        case spokenAck = "spoken_ack"
        case eventsPublished = "events_published"
    }
}

/// Health from GET /health. Nullable fields are intentional: the backend
/// reports NULL (not 0) where something is unmeasured, and the UI must not
/// turn that into a number.
struct Health: Decodable {
    struct Metrics: Decodable {
        let registered: Int?
        let healthy: Int?
        let passRate: Double?
        let totalDecisions: Int?
        let meanLatencyMs: Double?
    }

    let status: String?
    let statusLabel: String?
    let provenance: String?
    let models: Metrics?
    let providers: Metrics?
    let testing: Metrics?
    let laya: Metrics?

    enum CodingKeys: String, CodingKey {
        case status, provenance, models, providers, testing, laya
        case statusLabel = "status_label"
    }
}

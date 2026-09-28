import Foundation

/// A canonical AIS event, as returned by /events and /events/stream.
struct EventEnvelope: Decodable, Identifiable {
    let eventId: String?
    let traceId: String?
    let parentEventId: String?
    let eventType: String?
    let source: String?
    /// Top-level provenance, when the envelope carries one. Truth falls back to
    /// this when the payload itself does not name a provenance.
    let provenance: String?
    let temporalModality: String?
    let payload: [String: Any]?

    var id: String { eventId ?? UUID().uuidString }

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case traceId = "trace_id"
        case parentEventId = "parent_event_id"
        case eventType = "event_type"
        case source
        case provenance
        case temporalModality = "temporal_modality"
        case payload
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        eventId = try? c.decode(String.self, forKey: .eventId)
        traceId = try? c.decode(String.self, forKey: .traceId)
        parentEventId = try? c.decode(String.self, forKey: .parentEventId)
        eventType = try? c.decode(String.self, forKey: .eventType)
        source = try? c.decode(String.self, forKey: .source)
        provenance = try? c.decode(String.self, forKey: .provenance)
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

// MARK: - JARVIS
//
// Transcribed from backend/app/schemas/jarvis.py. The most important field
// here is `executed`: the backend tells us whether an action ACTUALLY ran.
// The UI must render that, and must never infer success from a 200 alone.

struct JarvisActionDetail: Decodable, Identifiable {
    let phrase: String?
    let action: String?
    let targetApp: String?
    let volumeLevel: Double?
    let timerSeconds: Double?
    let confidence: Double?
    let executed: Bool?
    let detail: String?

    var id: String { "\(action ?? "?")|\(targetApp ?? "?")|\(phrase ?? "?")" }

    enum CodingKeys: String, CodingKey {
        case phrase, action, detail
        case targetApp = "target_app"
        case volumeLevel = "volume_level"
        case timerSeconds = "timer_seconds"
        case confidence, executed
    }
}

struct JarvisTalkResponse: Decodable {
    let traceId: String?
    let utterance: String?
    /// COMMAND or QUESTION.
    let decisionType: String?
    let source: String?
    let latencyLayaMs: Double?
    let spokenAck: String?
    let audioBase64: String?
    let actions: [JarvisActionDetail]?
    let eventsPublished: Int?

    enum CodingKeys: String, CodingKey {
        case traceId = "trace_id"
        case utterance
        case decisionType = "decision_type"
        case source
        case latencyLayaMs = "latency_laya_ms"
        case spokenAck = "spoken_ack"
        case audioBase64 = "audio_base64"
        case actions
        case eventsPublished = "events_published"
    }

    /// True only when the backend reports at least one action that actually
    /// executed. A 200 with every action `executed=false` is NOT success.
    var didExecute: Bool {
        (actions ?? []).contains { $0.executed == true }
    }
}

/// GET /jarvis/status. Note `status` is a hardcoded "ONLINE" string on the
/// backend, NOT a live probe. It is rendered as a report, never as proof.
struct JarvisStatus: Decodable {
    let status: String?
    let service: String?
    let decisionLayer: String?
    let hardware: String?
    let llmProvider: String?
    let defaultModel: String?
    let ttsEngine: String?
    let spendRate: String?
    let capabilities: [String]?

    enum CodingKeys: String, CodingKey {
        case status, service, hardware, capabilities
        case decisionLayer = "decision_layer"
        case llmProvider = "llm_provider"
        case defaultModel = "default_model"
        case ttsEngine = "tts_engine"
        case spendRate = "spend_rate"
    }
}

/// Response of POST /jarvis/agent/run. Typed from the request model plus the
/// handler in app/api/jarvis.py; unconfirmed response fields stay absent
/// rather than being invented.
struct AgentRun: Decodable {
    let traceId: String?
    let goal: String?
    let maxSteps: Int?
    let status: String?
    let steps: [String]?

    enum CodingKeys: String, CodingKey {
        case traceId = "trace_id"
        case goal, status, steps
        case maxSteps = "max_steps"
    }
}

// MARK: - Laya
//
// Shapes below are transcribed from backend/app/schemas/laya.py. Only fields
// verified against that source are typed; anything not confirmed is left out
// rather than guessed, so a schema drift shows up as a missing value instead
// of a silently wrong one.

struct LayaChoiceResult: Decodable {
    let type: String?
    let selected: String?
    let distribution: [String: Double]?
}

struct LayaScoreResult: Decodable {
    let type: String?
    let expected: Double?
    let distribution: [String: Double]?
}

struct LayaNoulResult: Decodable {
    let type: String?
    let probabilityTrue: Double?

    enum CodingKeys: String, CodingKey {
        case type
        case probabilityTrue = "probability_true"
    }
}

/// A single question result. The backend models these as a discriminated
/// union keyed on `type`, with the variant's fields inline in the same
/// object -- there is no nested `value` wrapper.
struct LayaQuestion: Decodable {
    let choice: LayaChoiceResult?
    let score: LayaScoreResult?
    let noul: LayaNoulResult?
    let type: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let t = try? c.decode(String.self, forKey: .type)
        type = t
        choice = (t == "choice") ? try? LayaChoiceResult(from: decoder) : nil
        score  = (t == "score")  ? try? LayaScoreResult(from: decoder)  : nil
        noul   = (t == "noul")   ? try? LayaNoulResult(from: decoder)   : nil
    }

    enum CodingKeys: String, CodingKey {
        case type
    }
}

/// Response of POST /laya/evaluate.
struct LayaDecisionResponse: Decodable {
    let decisionId: String?
    let schemaVersion: String?
    let checkpoint: String?
    let decisionTimeMs: Double?
    let questions: [String: LayaQuestion]?
    let evidenceRefs: [String]?
    let applicability: String?
    let isFallback: Bool?
    let fallbackReason: String?
    let taskId: String?
    let modelId: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case decisionId = "decision_id"
        case schemaVersion = "schema_version"
        case checkpoint
        case decisionTimeMs = "decision_time_ms"
        case questions, evidenceRefs = "evidence_refs"
        case applicability, isFallback = "is_fallback"
        case fallbackReason = "fallback_reason"
        case taskId = "task_id"
        case modelId = "model_id"
        case createdAt = "created_at"
    }
}

/// Row of GET /laya/decisions. Note the backend persists `questions` as a JSON
/// *string* here, unlike the evaluate response, and `is_fallback` as an int.
struct LayaDecisionRecord: Decodable, Identifiable {
    let decisionId: String?
    let decisionType: String?
    let checkpoint: String?
    let decisionTimeMs: Double?
    let questions: String?
    let isFallback: Int?
    let fallbackReason: String?
    let taskId: String?
    let modelId: String?
    let createdAt: String?

    var id: String { decisionId ?? UUID().uuidString }

    enum CodingKeys: String, CodingKey {
        case decisionId = "decision_id"
        case decisionType = "decision_type"
        case checkpoint
        case decisionTimeMs = "decision_time_ms"
        case questions
        case isFallback = "is_fallback"
        case fallbackReason = "fallback_reason"
        case taskId = "task_id"
        case modelId = "model_id"
        case createdAt = "created_at"
    }
}

// MARK: - Learning loop
//
// NOTE the hyphen: the backend router is mounted at /learning-loop, not
// /learning_loop. Transcribed from backend/app/api/learning_loop.py.

struct LearningLoopRun: Decodable {
    let traceId: String?
    let loopId: String?
    let taskAId: String?
    let taskBId: String?
    let lessonId: String?
    let diagnosisId: String?
    let assessmentId: String?
    let gateId: String?
    let evidenceAId: String?
    let evidenceBId: String?
    let preventionWorked: Bool?
    let lessonStatus: String?
    let eventCount: Int?

    enum CodingKeys: String, CodingKey {
        case traceId = "trace_id"
        case loopId = "loop_id"
        case taskAId = "task_a_id"
        case taskBId = "task_b_id"
        case lessonId = "lesson_id"
        case diagnosisId = "diagnosis_id"
        case assessmentId = "assessment_id"
        case gateId = "gate_id"
        case evidenceAId = "evidence_a_id"
        case evidenceBId = "evidence_b_id"
        case preventionWorked = "prevention_worked"
        case lessonStatus = "lesson_status"
        case eventCount = "event_count"
    }
}

struct Lesson: Decodable, Identifiable {
    let memoryId: String?
    let lessonCondition: String?
    let preventionAction: String?
    let validationHash: String?
    let confidence: Double?
    let createdAt: String?

    var id: String { memoryId ?? UUID().uuidString }

    enum CodingKeys: String, CodingKey {
        case memoryId = "memory_id"
        case lessonCondition = "lesson_condition"
        case preventionAction = "prevention_action"
        case validationHash = "validation_hash"
        case confidence
        case createdAt = "created_at"
    }
}

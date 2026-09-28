import Foundation
import Combine

/// Truth vocabulary, mirroring the backend's precedence (commit 03520f4):
/// check `payload.provenance` BEFORE `temporal_modality`.
///
/// The rule that matters: an event is NEVER shown as VERIFIED_LIVE merely
/// because its type is `task.completed`. A seeded demo chain and a real
/// worker both emit that type; only provenance distinguishes them.
enum Truth {
    enum Badge {
        case verifiedLive
        case seededSimulated
        case projected
        case historical
        case unproven
        case unverifiable

        var label: String {
            switch self {
            case .verifiedLive: return "VERIFIED_LIVE"
            case .seededSimulated: return "SEEDED_SIMULATED"
            case .projected: return "PROJECTED_ESTIMATED"
            case .historical: return "HISTORICAL"
            case .unproven: return "CURRENT (unproven)"
            case .unverifiable: return "UNVERIFIABLE"
            }
        }
    }

    /// `REAL_EXECUTION` is the label the JARVIS endpoint stamps on events,
    /// including dry runs. It is a claim, not proof, so it is surfaced as
    /// unverified rather than trusted.
    static func badge(for event: EventEnvelope) -> Badge {
        let provenance = event.payload?["provenance"] as? String ?? event.provenance
        let modality = event.temporalModality

        if let provenance = provenance?.lowercased() {
            if provenance == "simulated" || provenance == "seeded" { return .seededSimulated }
            if provenance == "verified_live" { return .verifiedLive }
            if provenance == "real_execution" { return .unproven }
        }
        switch modality?.lowercased() {
        case "seeded_simulated", "simulated": return .seededSimulated
        case "projected": return .projected
        case "historical": return .historical
        case "current": return .unproven
        default: return .unverifiable
        }
    }
}

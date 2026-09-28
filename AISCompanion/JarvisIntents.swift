import Foundation
import AppIntents

/// Siri / Shortcuts bridge to the JARVIS host.
///
/// WHAT THIS CAN AND CANNOT DO
/// An iOS app can never take the wake word: "Hey Siri" always goes to
/// Apple's recogniser. What this intent does is give Siri a real verb --
/// it runs in the background, posts the utterance to the AIS host, and
/// returns a dialog that Siri speaks. So "Hey Siri, ask JARVIS to lock the
/// PC" reaches your host and the answer comes back out loud.
///
/// It is NOT a continuous listening session. Each request is a discrete
/// Siri invocation. The Android build is the one that can be a true
/// always-on assistant, via VoiceInteractionService.
///
/// TRUTH DISCIPLINE: if the host is unreachable the dialog says so. It
/// never claims a command succeeded, and it never invents a reply.
struct TalkToJarvisIntent: AppIntent {
    static var title: LocalizedStringResource = "Talk to JARVIS"
    static var description = IntentDescription(
        "Send an utterance to your AIS host and speak the reply.")
    static var openAppWhenRun = false

    @Parameter(title: "Say", requestValueDialog: "What should JARVIS do?")
    var utterance: String

    static var parameterSummary: some ParameterSummary {
        Summary("Ask JARVIS to \(\.$utterance)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return .result(dialog: "I didn't catch what to send to JARVIS.")
        }

        let api = AisApi()
        guard !api.authToken.isEmpty else {
            return .result(dialog: "JARVIS is not set up on this phone yet. Open the AIS app and add your host token under System.")
        }
        guard api.baseURL.host != "127.0.0.1" else {
            return .result(dialog: "JARVIS is still pointed at this device. Set your AIS host in the AIS app first.")
        }

        // dry_run=false: the user asked for a real command. Siri phrases are
        // explicit, so this is the intended behaviour, and the host is the
        // only thing that decides what actually executes.
        do {
            let reply = try await api.talk(text, dryRun: false)
            if let ack = reply.spokenAck, !ack.isEmpty {
                return .result(dialog: IntentDialog(stringLiteral: ack))
            }
            if let dt = reply.decisionType, !dt.isEmpty {
                return .result(dialog: "JARVIS handled that. Decision: \(dt).")
            }
            // The host accepted the request but produced nothing speakable.
            // Report that honestly rather than claiming success.
            return .result(dialog: "JARVIS accepted that, but gave me nothing to read back.")
        } catch let e as AisApi.ApiError {
            switch e {
            case .unreachable:
                return .result(dialog: "I can't reach your AIS host right now. Nothing was executed.")
            case .rejected(let code, _):
                return .result(dialog: "Your AIS host rejected that with HTTP \(code).")
            case .malformed:
                return .result(dialog: "I couldn't read the reply from your AIS host.")
            }
        } catch {
            return .result(dialog: "Something went wrong talking to JARVIS. Nothing was executed.")
        }
    }
}

/// Read-only health probe: "Hey Siri, what's AIS status?"
struct AisStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Get AIS status"
    static var description = IntentDescription("Report the AIS host health as reported by the backend.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let api = AisApi()
        guard !api.authToken.isEmpty else {
            return .result(dialog: "JARVIS is not set up on this phone yet.")
        }
        do {
            let h = try await api.health()
            let status = (h.statusLabel ?? h.status ?? "UNKNOWN").replacingOccurrences(of: "_", with: " ")
            // Quote the backend's own provenance rather than asserting health.
            if let p = h.provenance, !p.isEmpty {
                return .result(dialog: "AIS reports \(status). Provenance: \(p).")
            }
            return .result(dialog: "AIS reports \(status).")
        } catch let e as AisApi.ApiError {
            if case .unreachable = e {
                return .result(dialog: "I can't reach your AIS host right now.")
            }
            return .result(dialog: "Your AIS host didn't return a health status.")
        } catch {
            return .result(dialog: "Something went wrong reading AIS status.")
        }
    }
}

struct JarvisShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TalkToJarvisIntent(),
            phrases: [
                "Ask JARVIS with \(.applicationName)",
                "Talk to JARVIS with \(.applicationName)",
                "Tell JARVIS with \(.applicationName)",
                "\(.applicationName), ask JARVIS"
            ],
            shortTitle: "Talk to JARVIS",
            systemImageName: "waveform.circle"
        )
        AppShortcut(
            intent: AisStatusIntent(),
            phrases: [
                "Get \(.applicationName) status",
                "Check \(.applicationName) health",
                "Is \(.applicationName) online"
            ],
            shortTitle: "AIS status",
            systemImageName: "gauge.with.dots.needle.50percent"
        )
    }
}

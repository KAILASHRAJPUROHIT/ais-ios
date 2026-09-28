import SwiftUI

/// A single source of truth for "what do we actually know right now".
///
/// TRUTH DISCIPLINE: these four cases are distinct and must never be
/// collapsed. In particular `.unreachable` is NOT `.failed` and NOT
/// `.empty`, and `.unmeasured` is NOT zero.
enum LoadState<Value> {
    case idle
    case loading
    case loaded(Value)
    case empty
    case unreachable(String)
    case rejected(Int, String)

    var value: Value? {
        if case .loaded(let v) = self { return v }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    /// A short, honest status line. Never invents a value.
    var summary: String {
        switch self {
        case .idle: return "IDLE"
        case .loading: return "LOADING"
        case .loaded: return "LOADED"
        case .empty: return "NO DATA"
        case .unreachable: return "UNREACHABLE"
        case .rejected(let code, _): return "HTTP \(code)"
        }
    }

    var tint: Color {
        switch self {
        case .loaded: return Theme.good
        case .empty: return Theme.text
        case .loading, .idle: return Theme.dim
        case .unreachable: return Theme.warn
        case .rejected: return Theme.bad
        }
    }

    /// Full explanation, for a detail row.
    var detail: String {
        switch self {
        case .idle: return "Not requested yet."
        case .loading: return "Waiting for the host to respond."
        case .loaded: return "Received from the host."
        case .empty: return "The host responded successfully with zero records. This is an empty state, not a failure."
        case .unreachable(let m): return "Could not reach the host: \(m). Nothing was executed and nothing is known about the host state."
        case .rejected(let code, let body):
            let b = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return b.isEmpty ? "Host returned HTTP \(code)." : "Host returned HTTP \(code): \(b)"
        }
    }
}

/// Map an AisApi error into the matching state. A transport failure must
/// never be reported as a server rejection.
func stateFor<T>(_ error: Error) -> LoadState<T> {
    if let e = error as? AisApi.ApiError {
        switch e {
        case .unreachable(let m): return .unreachable(m)
        case .rejected(let c, let b): return .rejected(c, b)
        case .malformed: return .rejected(0, "Unreadable response from host.")
        }
    }
    return .unreachable(error.localizedDescription)
}

/// A status banner that always states what is known.
struct StateBanner<Value>: View {
    let state: LoadState<Value>
    var body: some View {
        HStack(spacing: 8) {
            if state.isLoading {
                ProgressView().controlSize(.small)
            }
            Text(state.summary)
                .font(.caption2.weight(.semibold))
                .foregroundColor(state.tint)
            Spacer(minLength: 0)
        }
    }
}

/// Key/value row used across the dashboard screens.
struct KV: View {
    let key: String
    let value: String
    var mono: Bool = true
    var tint: Color = Theme.text

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(key)
                .font(.caption2)
                .foregroundColor(Theme.dim)
                .frame(width: 116, alignment: .leading)
            Text(value.isEmpty ? "\u{2014}" : value)
                .font(mono ? .system(size: 12, design: .monospaced) : .system(size: 12))
                .foregroundColor(tint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }
}

/// Section header, matching the existing uppercase convention.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundColor(Theme.dim)
    }
}

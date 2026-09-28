import SwiftUI

/// Update availability and host settings.
///
/// iOS CANNOT install an update by itself. Every path to installing an IPA --
/// App Store, TestFlight, or sideloading -- requires a human in the app or on
/// the device. So this screen checks, reports, and links out. It never claims
/// an update was installed.
struct UpdateView: View {
    @State private var state = UpdateState.unknown
    @State private var manifestInput = ""
    @State private var verifying = false
    @State private var verifyResult: String?

    private let currentVersion = Bundle.main
        .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("UPDATE \u{00B7} installed \(currentVersion)")
                Spacer()
                if state == .checking {
                    ProgressView().controlSize(.small)
                } else {
                    Button { check() } label: {
                        Image(systemName: "arrow.clockwise").font(.caption)
                    }
                }
            }

            switch state {
            case .unknown:
                Text("No update manifest is configured. Until one is set, this app cannot tell you a newer build exists.")
                    .font(.caption2).foregroundColor(Theme.dim)
            case .checking:
                Text("Checking\u{2026}").font(.caption2).foregroundColor(Theme.dim)
            case .upToDate(let cur, let latest):
                KV(key: "status", value: "UP TO DATE", tint: Theme.good)
                KV(key: "installed", value: cur)
                KV(key: "latest", value: latest)
            case .available(let cur, let latest, let url, let sha, let notes):
                KV(key: "status", value: "UPDATE AVAILABLE", tint: Theme.warn)
                KV(key: "installed", value: cur)
                KV(key: "latest", value: latest)
                if let n = notes, !n.isEmpty {
                    Text(n).font(.caption2).foregroundColor(Theme.text)
                }
                Link("DOWNLOAD BUILD", destination: url)
                    .font(.caption.weight(.semibold))
                Text("iOS will not install this for you. Sideload it with Sideloadly, or install via TestFlight.")
                    .font(.caption2).foregroundColor(Theme.warn)
                if let sha, !sha.isEmpty {
                    Button(verifying ? "VERIFYING\u{2026}" : "VERIFY DOWNLOAD") { verify(url: url, expected: sha) }
                        .font(.caption.weight(.semibold))
                        .disabled(verifying)
                    if let v = verifyResult {
                        Text(v).font(.caption2).foregroundColor(Theme.text)
                    }
                }
            case .unreachable(let m):
                KV(key: "status", value: "UNREACHABLE", tint: Theme.warn)
                Text(m).font(.caption2).foregroundColor(Theme.dim)
            case .malformed(let m):
                KV(key: "status", value: "MANIFEST ERROR", tint: Theme.bad)
                Text(m).font(.caption2).foregroundColor(Theme.dim)
            }

            Divider().overlay(Color.white.opacity(0.1))

            SectionLabel("UPDATE MANIFEST URL")
            TextField("https://.../update.json", text: $manifestInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            Button("SAVE MANIFEST") {
                UpdateChecker.setManifestURL(manifestInput)
            }
            .font(.caption.weight(.semibold))
        }
    }

    private func check() {
        state = .checking
        Task { state = await UpdateChecker.check(currentVersion: currentVersion) }
    }

    private func verify(url: URL, expected: String) {
        verifying = true
        verifyResult = nil
        Task {
            defer { verifying = false }
            guard let data = try? await Data(contentsOf: url) else {
                verifyResult = "Could not download the file to verify."
                return
            }
            let digest = SHA256Digest.hex(data)
            verifyResult = (digest == expected.lowercased())
                ? "SHA-256 matches the manifest. The download is intact."
                : "SHA-256 MISMATCH. Expected \(expected), got \(digest). Do not install this file."
        }
    }
}

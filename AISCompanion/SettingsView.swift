import SwiftUI

/// Host + bearer token configuration.
///
/// Stored in UserDefaults on the device only. The token is never logged and
/// never sent anywhere except the configured AIS host.
struct SettingsView: View {
    @State private var host: String = ""
    @State private var token: String = ""
    @State private var saved = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("AIS HOST")
                                .font(.caption2).foregroundColor(Theme.dim)
                            TextField("https://ai.ambicdigital.in", text: $host)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                                .padding(10)
                                .background(Theme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8)
                                    .stroke(token.isEmpty ? Color.orange : Theme.accent))
                            Text(token.isEmpty
                                 ? "No token set \u{2014} every API call will return 401."
                                 : "Token set (\(token.count) chars).")
                                .font(.caption2)
                                .foregroundColor(token.isEmpty ? Theme.warn : Theme.dim)

                            Text("BEARER TOKEN")
                                .font(.caption2).foregroundColor(Theme.dim)
                            SecureField("AIS_AUTH_TOKEN", text: $token)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(10)
                                .background(Theme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.accent))

                            Button("SAVE") { save() }
                                .buttonStyle(.borderedProminent).tint(Theme.accent)
                                .disabled(host.isEmpty)

                            if saved {
                                Text("Saved. Reopen the app to reload data.")
                                    .font(.caption).foregroundColor(Theme.good)
                            }
                        }
                        .card()

                        VStack(alignment: .leading, spacing: 6) {
                            Text("iOS NOTES").font(.caption2).foregroundColor(Theme.dim)
                            Text("""
                            Voice: tap-to-speak records audio and posts it to your AIS
                            host, where Whisper runs.

                            Always-on wake-word listening is not possible in this app:
                            iOS suspends the microphone for background apps, so
                            listening only works while the app is in the foreground.

                            Token rotation (on the AIS host):
                              uv run python -m app.core.auth_token --set
                            """)
                            .font(.caption).foregroundColor(Theme.dim)
                        }
                        .card()
                    }
                    .padding(14)
                }
            }
            .navigationTitle("HOST")
            .onAppear(perform: load)
        }
    }

    private func load() {
        let api = AisApi()
        host = api.baseURL.absoluteString
        token = api.authToken
    }

    private func save() {
        var h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        while h.hasSuffix("/") { h.removeLast() }
        UserDefaults.standard.set(h, forKey: "aisBaseURL")
        UserDefaults.standard.set(
            token.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "aisAuthToken")
        saved = true
    }
}

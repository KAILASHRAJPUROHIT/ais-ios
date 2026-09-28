import SwiftUI

/// Host + bearer token configuration.
///
/// Stored in UserDefaults on the device only. The token is never logged and
/// never sent anywhere except the configured AIS host.
struct SettingsView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView { SettingsContent() }
            }
            .navigationTitle("HOST")
        }
    }
}

/// The settings form without its own navigation chrome, so it can be embedded
/// inside another screen's ScrollView. A nested NavigationStack inside a
/// ScrollView produces broken scrolling and a duplicate title bar.
struct SettingsContent: View {
    @State private var host: String = ""
    @State private var token: String = ""
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("AIS HOST")
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

                SectionLabel("BEARER TOKEN")
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
                SectionLabel("iOS NOTES")
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
        .onAppear(perform: load)
    }

    private func load() {
        let api = AisApi()
        host = api.baseURL.absoluteString
        token = api.authToken
    }

    private func save() {
        var h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        while h.hasSuffix("/") { h.removeLast() }
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(h, forKey: "aisBaseURL")
        // Write to the Keychain, then remove the insecure UserDefaults copy
        // so the token is not left readable in a backup or a rooted image.
        _ = SecureStore().saveToken(t)
        UserDefaults.standard.removeObject(forKey: "aisAuthToken")
        saved = true
    }
}

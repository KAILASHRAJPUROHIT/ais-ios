import Foundation
import Security

/// Per-device secret storage backed by the iOS Keychain.
///
/// SECURITY: the bearer token grants command execution on the AIS host
/// (`/jarvis/talk` can lock the PC). It must never be baked into the binary
/// and must not sit in UserDefaults, which is an unencrypted plist readable
/// from a device backup or a jailbroken filesystem.
///
/// The token is provisioned per device (pasted once at setup) and is scoped
/// to this app and this device only.
struct SecureStore {
    private let service = "in.ambicdigital.companion"
    private let account = "aisAuthToken"

    /// Store or replace the token. Uses `kSecAttrAccessibleAfterFirstUnlock`
    /// so a background refresh can still read it, but the item is not
    /// readable while the device is locked at boot.
    @discardableResult
    func saveToken(_ token: String) -> Bool {
        deleteToken()
        guard !token.isEmpty else { return true }
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    /// Returns the stored token, or "" when none is provisioned.
    func readToken() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let s = String(data: data, encoding: .utf8) else {
            return ""
        }
        return s
    }

    @discardableResult
    func deleteToken() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    var hasToken: Bool { !readToken().isEmpty }

    /// True when a token exists only in the legacy insecure location. Used to
    /// offer a one-time migration rather than silently losing the value.
    func hasLegacyUserDefaultsToken() -> Bool {
        guard let t = UserDefaults.standard.string(forKey: "aisAuthToken") else { return false }
        return !t.isEmpty
    }
}

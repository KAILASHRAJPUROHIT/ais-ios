import Foundation

/// SHA-256 of downloaded bytes.
///
/// Implemented locally rather than importing CryptoKit so the same logic is
/// obvious and does not depend on framework availability. Returns lowercase
/// hex, matching how digests are written in an update manifest.
enum SHA256Digest {

    static func hex(_ data: Data) -> String {
        digest(data).map { String(format: "%02x", $0) }.joined()
    }

    static func digest(_ data: Data) -> [UInt8] {
        let k: [UInt32] = [
            0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
            0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
            0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
            0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
            0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
            0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
            0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
            0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2]

        var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                           0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]

        var msg = [UInt8](data)
        let bitLen = UInt64(msg.count) * 8
        msg.append(0x80)
        while msg.count % 64 != 56 { msg.append(0) }
        for i in (0..<8).reversed() {
            msg.append(UInt8((bitLen >> (UInt64(i) * 8)) & 0xff))
        }

        var w = [UInt32](repeating: 0, count: 64)
        var chunk = 0
        while chunk < msg.count {
            for i in 0..<16 {
                let o = chunk + i * 4
                w[i] = (UInt32(msg[o]) << 24) | (UInt32(msg[o+1]) << 16) |
                       (UInt32(msg[o+2]) << 8) | UInt32(msg[o+3])
            }
            for i in 16..<64 {
                let s0 = rotr(w[i-15], 7) ^ rotr(w[i-15], 18) ^ (w[i-15] >> 3)
                let s1 = rotr(w[i-2], 17) ^ rotr(w[i-2], 19) ^ (w[i-2] >> 10)
                w[i] = w[i-16] &+ s0 &+ w[i-7] &+ s1
            }
            var a = h[0], b = h[1], c = h[2], d = h[3]
            var e = h[4], f = h[5], g = h[6], hh = h[7]
            for i in 0..<64 {
                let S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ (~e & g)
                let t1 = hh &+ S1 &+ ch &+ k[i] &+ w[i]
                let S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let t2 = S0 &+ maj
                hh = g; g = f; f = e; e = d &+ t1
                d = c; c = b; b = a; a = t1 &+ t2
            }
            h[0] = h[0] &+ a; h[1] = h[1] &+ b; h[2] = h[2] &+ c; h[3] = h[3] &+ d
            h[4] = h[4] &+ e; h[5] = h[5] &+ f; h[6] = h[6] &+ g; h[7] = h[7] &+ hh
            chunk += 64
        }

        var out: [UInt8] = []
        for v in h {
            out.append(UInt8((v >> 24) & 0xff)); out.append(UInt8((v >> 16) & 0xff))
            out.append(UInt8((v >> 8) & 0xff));  out.append(UInt8(v & 0xff))
        }
        return out
    }

    private static func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }
}


/// Update availability check.
///
/// WHAT THIS CAN AND CANNOT DO
///
/// iOS cannot install an update itself. Installing is always a user action on
/// the device, so this checks and REPORTS. It never claims an update was
/// installed and never requests a background install iOS will refuse.
///
/// The manifest is a small JSON document the user controls, so a build can be
/// published without shipping a new binary:
///
///   { "ios":     { "version": "0.2.0", "url": "https://.../app.ipa",
///                  "sha256": "...", "notes": "Adds the Learn tab." },
///     "android": { "version": "0.2.0", "url": "https://.../app.apk",
///                  "sha256": "..." } }
///
/// `sha256` is optional but recommended: it lets the app verify what it
/// downloaded before a human installs it. `version` compares semantically, so
/// 0.10.0 correctly beats 0.9.0.
struct UpdateManifest: Decodable {
    struct Platform: Decodable {
        let version: String?
        let url: String?
        let sha256: String?
        let notes: String?
    }
    let ios: Platform?
    let android: Platform?
}

enum UpdateState: Equatable {
    case unknown
    case checking
    case upToDate(current: String, latest: String)
    /// A newer build exists. iOS can never install it without the user.
    case available(current: String, latest: String, url: URL, sha256: String?, notes: String?)
    case unreachable(String)
    case malformed(String)
}

enum UpdateChecker {

    private static let manifestKey = "aisUpdateManifestUrl"

    /// Where to look for the manifest. Empty means "not configured", reported
    /// as `unknown` rather than silently treated as up to date.
    static func manifestURL() -> URL? {
        guard let raw = UserDefaults.standard.string(forKey: manifestKey),
              !raw.isEmpty,
              let u = URL(string: raw) else { return nil }
        return u
    }

    static func setManifestURL(_ raw: String) {
        var u = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !u.isEmpty && !u.hasPrefix("http://") && !u.hasPrefix("https://") {
            u = "https://" + u
        }
        UserDefaults.standard.set(u, forKey: manifestKey)
    }

    /// Semantic compare. True when `latest` is strictly newer.
    static func isNewer(_ latest: String, than current: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let l = parts(latest), c = parts(current)
        for i in 0..<max(l.count, c.count) {
            let lv = i < l.count ? l[i] : 0
            let cv = i < c.count ? c[i] : 0
            if lv != cv { return lv > cv }
        }
        return false
    }

    static func check(currentVersion: String, platform: String = "ios") async -> UpdateState {
        guard let url = manifestURL() else { return .unknown }
        return await check(manifestURL: url, currentVersion: currentVersion, platform: platform)
    }

    static func check(manifestURL url: URL, currentVersion: String, platform: String) async -> UpdateState {
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 10
            // Bypass any intermediary cache so a newly published build is seen.
            req.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: req)

            guard let http = response as? HTTPURLResponse else {
                return .malformed("No HTTP response.")
            }
            guard (200..<300).contains(http.statusCode) else {
                return .malformed("Host returned HTTP \(http.statusCode).")
            }

            let manifest = try JSONDecoder().decode(UpdateManifest.self, from: data)
            let entry: UpdateManifest.Platform? = platform == "ios" ? manifest.ios : manifest.android

            guard let latest = entry?.version else {
                return .malformed("Manifest has no '\(platform)' entry.")
            }
            if !isNewer(latest, than: currentVersion) {
                return .upToDate(current: currentVersion, latest: latest)
            }
            guard let raw = entry?.url, let u = URL(string: raw) else {
                return .malformed("Update is newer but has no usable URL.")
            }
            return .available(current: currentVersion, latest: latest, url: u,
                              sha256: entry?.sha256, notes: entry?.notes)
        } catch let e as AisApi.ApiError {
            if case .unreachable(let m) = e { return .unreachable(m) }
            return .malformed("Could not read the update manifest.")
        } catch {
            return .unreachable(error.localizedDescription)
        }
    }
}

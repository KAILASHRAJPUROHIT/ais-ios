# AIS Companion — iOS

Native SwiftUI client for the Ambic Intelligence System (AIS).

Self-contained: 10 Swift files, no third-party dependencies. It talks to your
AIS host over HTTPS and implements no AI itself.

## Build the .ipa

The GitHub Actions workflow (`.github/workflows/ios-ipa.yml`) builds an
**unsigned** `.ipa` on a macOS runner.

1. Push this repo to GitHub
2. Open **Actions → "Build iOS IPA"**
3. Download the artifact and unzip it
4. Re-sign the `.ipa` with your Apple ID (Sideloadly / AltStore)

## Why the build runs on GitHub

An iOS app cannot be compiled on Windows or Linux. Apple's iOS SDK and Xcode
are macOS-only, and the SDK licence forbids use on other platforms. GitHub's
macOS runners provide the genuine Xcode toolchain.

Locally, with Xcode installed:

```bash
brew install xcodegen
xcodegen generate
open AISCompanion.xcodeproj
```

## Signing and the 7-day limit

The build produces an **unsigned** ipa. Sideloadly / AltStore apply your own
Apple ID signature at install time.

**A free Apple ID produces a 7-day provisioning profile.** The app must be
re-signed and reinstalled each week. No build setting can extend this — it is
imposed by Apple on free provisioning. A paid Apple Developer Program
membership ($99/year) issues a 1-year profile instead.

If weekly re-signing is not acceptable, use the PWA instead, which never
expires: <https://ai.ambicdigital.in/pwa/>

## First run

Open the app, go to the **HOST** tab, and enter:

- **AIS host** — e.g. `https://ai.ambicdigital.in`
- **Bearer token** — your `AIS_AUTH_TOKEN` (see `backend/.env` on the host)

Both are stored in `UserDefaults` on the device only. The app shows
"TOKEN NOT SET" in amber until a token is saved.

## Truth discipline

This client follows the backend's rules from commit `03520f4`:

- Health values pass through unchanged; nothing is fabricated
- A NULL measurement renders as `UNMEASURED`, never `0.0`
- An unreachable host renders `UNREACHABLE` — neither healthy nor failed
- Every event carries a truth badge; provenance decides, never event type
- A disconnected stream shows `DISCONNECTED`, not an empty-but-calm list
- Dry runs are labelled as not executed

## Known iOS limits

- **No always-on wake-word listening.** iOS suspends the microphone for
  background apps, so listening only works in the foreground. Tap-to-speak
  works and posts audio to the AIS host, where Whisper transcribes it.
- Requires iOS 16.0 or later.

# Releasing the Mac app

Source publication and a public installer are separate milestones. The current source is MIT; the installer remains closed.

## Local preparation

Build and run the README checks. Keep the version and build number in `macos/scripts/build-app.sh` aligned with `web/dist/release.json`. Use a new output directory for every verification run. Public Git history must exclude local evidence, private test text, `.app` bundles, hosting metadata and credentials.

```sh
bash macos/scripts/build-app.sh
python3 macos/scripts/release-macos.py preflight --app build/idkthen.app
```

A nonzero preflight is expected without a Developer ID signature. The build script's ad-hoc or Apple Development signature is not sufficient for public distribution.

## Owner prerequisites

The owner must enroll in the Apple Developer Program, accept its agreements, create a Developer ID Application certificate, and make the signing identity available in the local Keychain. Apple account authentication, payments and macOS unlocks must be completed by the owner. Keep the private key private.

Store notarization credentials as a local `notarytool` Keychain profile using Apple's documented workflow; do not commit credentials or paste them into issue reports. No App Store submission is required for this direct-download route.

Official references: [Developer ID](https://developer.apple.com/developer-id/), [notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [customizing notarization](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

## Sign, validate, notarize and package

Replace the example identity/profile locally. The signing command writes a new bundle and refuses to overwrite an existing path.

```sh
python3 macos/scripts/release-macos.py sign   --app build/idkthen.app --output release-output/idkthen.app   --identity 'Developer ID Application: YOUR NAME (TEAMID)'
python3 macos/scripts/verify-candidate.py   --app release-output/idkthen.app --web web --output verification/signed-001
```

Complete every pending check in `verification/signed-001/validation-evidence.json` against that exact signed executable. Record the environment and concrete observations. Do not copy a pass from an older binary. At minimum, verify TextEdit, Safari and Chrome correction plus Undo, protected fields, real IME/paste, sustained typing, fresh installation, login/wake, permission recovery, VoiceOver, minimum supported macOS, update/removal and the global shortcut. Use another Mac/account for fresh-install testing.

```sh
python3 macos/scripts/release-macos.py notarize   --app release-output/idkthen.app --keychain-profile idkthen-notary
python3 macos/scripts/release-macos.py package   --app release-output/idkthen.app   --evidence verification/signed-001/validation-evidence.json   --output release-output/package-0.18.0   --download-url https://pairtype-preview.yeyen17.chatgpt.site/downloads/idkthen-0.18.0.zip
```

The tool requires Developer ID, Hardened Runtime, timestamp, Apple acceptance, a stapled ticket, Gatekeeper and completed evidence. It never disables quarantine or Gatekeeper.

## Publish the verified artifact

GitHub hosts source and development notes. The first installer uses the existing website's same-origin, versioned `downloads/` path so its manifest validation remains narrow. Do not put an unsigned app into GitHub Releases as an ordinary download.

```sh
python3 macos/scripts/release-macos.py stage-website   --release release-output/package-0.18.0 --site web   --site-url https://pairtype-preview.yeyen17.chatgpt.site
npm test --prefix web
```

This revalidates the ZIP and stages the file plus release manifest atomically; it does not publish. Publish the checked website source through its existing hosting workflow. Verify anonymous access, the hosted ZIP SHA-256, the version label and a quarantined download on a clean Mac. Retain prior immutable versions. To withdraw a broken release, close the manifest download gate; never replace an existing version with different bytes.

There is no automatic updater in this preview. Each release should include clear migration and compatibility notes.

# Validation status — 0.18.0 (28)

This is a source preview, not a general-release approval. A local build and synthetic tests do not prove reliable typing in every app.

## Confirmed locally

- 130 Swift core tests passed, including new regressions for bulk input followed by typing, pasted unfinished words, field activation and emoji/UTF-16 ranges.
- 83 web tests passed, covering selected languages, conservative correction, Unicode, recovery, native edit validation and the closed download gate.
- Chrome and Safari web preview: `chromedptj ` becomes `chrome에서 `; standard Undo restores the original and Redo reapplies the correction. Safari requires correction after the original input transaction finishes. The queued edit rechecks the exact text, selection, focus and composition state.

The new Mac guard excludes words from changes that cannot be classified as small typing edits. It also fixes the previous behavior where a skipped large input could be corrected on the next small keystroke. This deliberately does not convert an atomic large burst: Accessibility alone cannot reliably tell it apart from paste. The inspection window is anchored to the first notification rather than continually delayed.

## Remaining release gates

- Developer ID signing, notarization, stapling and Gatekeeper acceptance.
- Integration checks on the final signed binary, including real physical typing and IME switching, supported Safari/Chrome editors, the global Undo shortcut, login/wake and permission recovery.
- VoiceOver, fresh installation/update/removal on a second Mac/account, and the oldest macOS version advertised for download.
- Independent everyday-use feedback and false-correction rates. No user accuracy, battery-life or broad latency claim is made.

The frozen corpus passed 127 of 130 authored scenarios on this build. Three French/Portuguese accent-recovery misses remain. This is separate from the 130 passing core tests and is not a representative user dataset.

The local candidate runner passed all 18 check groups on macOS 27.0.1 / arm64, including signature integrity (development signing only), core tests, release-tool tests and synthetic app checks. The tested executable SHA-256 is `7555db6cff750f5e9105fe8864ec388ae0779de924a33f1c750a3c31474cdf7f`. Native menu-bar startup retained the existing four-language selection and three enabled apps. A new controlled Chrome native-integration attempt did not produce a correction through injected input; it is not counted as an OS-integration pass. Real foreground typing remains an open gate.

The release script refuses to package a public installer unless evidence for all required checks matches the exact signed executable hash. Evidence is local and excluded from Git; do not publish private test text or screenshots.

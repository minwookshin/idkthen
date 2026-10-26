# Validation status — 0.18.1 (29)

A source preview. The public Mac installer remains closed until the distribution and real-device checks below pass.

## Confirmed on this build

- All 18 automated check groups passed: 137 Swift core tests, 85 web tests, release tooling, app lifecycle and synthetic app checks.
- The frozen authored corpus passed **130/130**, up from 127/130. Three French/Portuguese misses now use bounded nearby-phrase rules. Valid spellings, names, literal text and conflicts with another enabled language remain protected. This is not a user accuracy estimate.
- Controlled native Chrome 155 textarea: `dkssud → 안녕`, `gkdl → 하이` and `chromedptj → chrome에서` applied once. Menu-button Undo restored the original word while preserving text typed afterward.
- Controlled native Chrome contenteditable: a new word corrected while surrounding bold/italic nodes and emoji survived. An existing unobserved word was left alone. Pasted text stayed unchanged on the next keystroke; single-line, password and read-only fields were excluded.
- A legacy PairType process was found running alongside idkthen and reproduced duplicate corrections. The new build pauses its live session when another copy is detected and checks for conflicts again before writing. The conflict message and recovery after quitting the old copy were checked; lifecycle tests cover startup, later conflicts and preserving an explicit Pause.
- Web preview: the three new French/Portuguese examples corrected through the actual input box. Safari 27.0.1 correction and native browser Undo/Redo passed with the Mac app paused. Desktop and 390px/320px responsive layouts were inspected. Responsive checks are not physical iPhone testing.

Local environment: macOS 27.0.1, Apple silicon. The executable is Apple Development signed, **not Developer ID signed or notarized**. SHA-256: `ce430938c977d128cc40f4217e1a41916dae5185827e41b167d07d116aa89635`.

The browser fixture contains no correction engine. Tests used synthetic text and tool-driven input. Two sampled native correction events arrived approximately 115 ms and 75 ms after the boundary input; this is a narrow observation, not a latency, battery-life or everyday reliability claim.

## Before a public Mac installer

- Developer ID signing, notarization, stapling and Gatekeeper acceptance.
- Physical sustained typing, real IME changes and the global Undo shortcut on the exact signed binary. The menu Undo passed; injected global shortcut input was inconclusive.
- Supported Safari/Chrome editors, login/wake, permission recovery, VoiceOver, fresh installation/update/removal on a second Mac/account, and the oldest advertised macOS version.
- Independent everyday-use feedback, particularly unwanted corrections and skipped typing.

The Mac fast path still intentionally skips large, unobserved insertions. Accessibility cannot reliably distinguish an atomic paste from a whole-word notification burst. It also prevents a skipped word from being changed by a later keystroke. It does not read global keystrokes or the clipboard.

Local evidence is tied to the executable hash and excluded from Git. Release packaging refuses a public installer unless all required evidence matches the final signed binary. Do not publish private test text or screenshots.

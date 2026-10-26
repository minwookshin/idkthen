# Contributing

Use a small branch for a focused change. Explain the original input, enabled languages, intended result, and why changing it automatically is safe. Include counterexamples where the same letters are intentional English, a name, code, slang or a different selected language.

Run `swift test --package-path macos -c release`, `python3 macos/scripts/test-release.py`, `python3 macos/scripts/test-candidate.py` and `npm test --prefix web` for relevant changes. Native integration checks must use a built `.app`, not just core unit tests. Do not label synthetic tests as user accuracy or OS integration results.

Keep the menu bar UI small. Do not introduce global keystroke capture, clipboard polling, remote text inference, or blanket replacement of an editor's whole value. Stale snapshots must refuse an edit; Undo must preserve later typing. Ambiguity should reduce automatic changes.

Report browser, macOS and app versions, keyboard layout, selected languages and correction mode. Share only an invented reproducer. Never attach Accessibility databases, full logs, chat transcripts, account details or signing credentials.

By submitting a contribution, you agree to license your contribution under the repository's MIT license. No CLA or sign-off is required.

# idkthen

A small macOS menu bar app for people who write in more than one language.
It helps recover keyboard-layout mix-ups and missing accents while keeping intentional language mixing intact.

`chromedptj` → `chrome에서` · `manana` → `mañana` · `bientot` → `bientôt`

**Development preview.** The source is open under MIT. The public Mac installer is not ready: Developer ID signing, Apple notarization and the remaining compatibility checks are still required. A successful build is not a claim that every app or language works.

[Try the browser preview](https://pairtype-preview.yeyen17.chatgpt.site/) · [Release status](docs/validation.md) · [Privacy](docs/privacy.md) · [Build and release](docs/releasing.md)

## What it does

- Lives in the menu bar, with On/Off, per-app pause and recent-correction Undo.
- Keeps English enabled and lets you choose up to three partner languages, globally or for each enabled app.
- Offers Automatic and Suggest modes. Ambiguous readings wait for a choice.
- Remembers explicitly kept words and repeated correction rejections locally.
- Uses a small deterministic fast path; optional Apple on-device context can veto uncertain corrections. It does not fetch current memes or send writing to a language-model API.

The catalog is English, Spanish, French, Korean, Portuguese, German, Italian, Russian and Ukrainian. Accent recovery and keyboard-layout recovery have different coverage. Korean uses standard two-set positions; Cyrillic support uses PC layouts, not phonetic keyboards. Ukrainian automatic recovery also depends on a reliable system dictionary. This is not translation, grammar rewriting, or universal autocorrect.

## Build the Mac app

Use an Apple silicon Mac, Xcode 26 or newer with its command-line tools selected, and Python 3. The deployment target is macOS 14; local validation currently covers macOS 27.0.1 only. Older macOS versions and Intel are unverified.

```sh
swift test --package-path macos -c release
bash macos/scripts/build-app.sh
```

The bundle is created at `build/idkthen.app`. This is a local, ad-hoc-signed development build. For repeated local builds, optionally set `IDKTHEN_SIGN_IDENTITY` to your existing Apple Development identity. This does not make a public distribution build.

Open the built app yourself, start with the built-in typing exercise, then add a test app in Settings. Accessibility access is needed only to read and replace text in other enabled apps. Start in Suggest mode. Unsupported editors, password fields, search fields, terminals and code editors are skipped. Return does not trigger a correction.

Do not run old PairType and idkthen copies together. The internal bundle identifier remains `dev.pairtype.preview` to preserve existing preferences. macOS may require Accessibility approval to be refreshed after replacing a development build. See [migration and removal](docs/setup.md).

## Run the browser preview

Node.js 22+ and Python 3 are enough; there are no npm dependencies.

```sh
cd web
npm test
npm run dev
```

Open `http://127.0.0.1:4173`. The browser demo only edits its own textarea. It uses a smaller authored engine and does not install the Mac app or prove OS-wide compatibility. Edit `content-pages.json` for help pages, then run `npm run build` to regenerate them.

## Verify a candidate

```sh
python3 macos/scripts/verify-candidate.py   --app build/idkthen.app --web web --output verification/local-001
```

The command writes local logs and evidence tied to the binary hash. It never marks manual OS checks as passed. [Validation scope and open gates](docs/validation.md) explain what remains before a public installer.

## Contribute

Small, reproducible input cases are especially useful. Use invented text rather than a private conversation. See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

MIT © Minwook Shin. Apple frameworks and system dictionaries remain provided by macOS; this repository does not redistribute them.

# idkthen

A small Mac menu bar app for typing in more than one language.
Recover keyboard mix-ups and missing accents without rewriting your message.

`chromedptj` → `chrome에서` · `manana` → `mañana` · `bientot` → `bientôt`

[Try it in your browser](https://pairtype-preview.yeyen17.chatgpt.site/) · [Watch the demo](https://pairtype-preview.yeyen17.chatgpt.site/demo) · [Release status](docs/validation.md)

- Choose English and up to three more languages, with optional settings per app.
- Switch between automatic corrections and suggestions. Unclear readings stay your choice.
- Pause from the menu bar, undo a correction, and keep words you meant to type.
- Writing stays on your Mac. No account, server, or API key.

The nine-language catalog includes English, Spanish, French, Korean, Portuguese, German, Italian, Russian and Ukrainian. Coverage varies by language, keyboard and editor. This is accent and keyboard-layout recovery, not translation.

## Run locally

Apple silicon Mac · Xcode 26+ · Python 3

```sh
swift test --package-path macos -c release
bash macos/scripts/build-app.sh
```

Open `build/idkthen.app`. Start with the built-in typing exercise, then enable a test app. Accessibility access is needed for editing text in other apps. [Setup and removal →](docs/setup.md)

**Source preview:** a signed, notarized public Mac installer is still pending. Chrome and Safari support is limited to supported editable fields. See [tested behavior and remaining checks](docs/validation.md).

For the browser preview: `cd web && npm test && npm run dev` (Node.js 22+). It only changes text inside its own input box.

[Contributing](CONTRIBUTING.md) · [Build and release](docs/releasing.md) · [Privacy](docs/privacy.md) · [Security](SECURITY.md) · [MIT license](LICENSE)

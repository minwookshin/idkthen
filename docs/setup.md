# Setup, migration and removal

For a source build, follow the README. For a future verified installer, download the versioned ZIP from the website, verify its published checksum, move `idkthen.app` to Applications and launch it. Do not bypass macOS security warnings.

1. Use Getting Started / Try Typing inside the app.
2. Select English plus one to three partner languages. Choose Suggest for initial trials.
3. In Settings, add one target app and allow macOS Accessibility when requested.
4. Enable While You Type and test a multiline field using invented text.
5. Try the recent-correction Undo button after continuing the sentence. The optional global Undo shortcut is separate from the target app's own Undo.

On/Off and temporary app pause are available from the menu bar. Open at Login is optional and available after installation in Applications; macOS controls its approval.

## Updating from PairType

Quit the old app before opening idkthen. The bundle identifier and preference keys are deliberately retained. This avoids silently discarding language profiles, kept words or exclusions. Do not keep both running. A development signature or changed bundle path can require renewed Accessibility approval; this must be handled in System Settings by the user. Signing the distribution build consistently is part of the future update path.

## If a field does not work

Check the app's connection status, enabled-app list, selected keyboard layout and Accessibility state. Search bars, passwords, terminals, code editors, canvas editors and some rich editors are intentionally unsupported. Use Review Text as a manual fallback. Large atomic changes, including paste, are ignored; the app cannot reliably distinguish them from coalesced typing notifications and should not change them later.

## Remove

Turn off While You Type and Open at Login, quit idkthen, then remove the app using Finder. Remove its Accessibility entry in System Settings if desired. Use the app's preference reset/forget controls before removal if you want to clear saved words and profiles. Do not delete system privacy databases. There is no background daemon or automatic updater to uninstall.

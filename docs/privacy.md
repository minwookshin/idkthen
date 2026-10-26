# Privacy

idkthen's native correction pipeline runs on the Mac. There is no account, analytics SDK, remote inference endpoint or automatic diagnostic upload in this source.

When While You Type is enabled, the app observes Accessibility notifications for the foreground app only if that app is enabled by the user. It reads the focused supported text field to calculate and validate a correction. It does not use a global keyboard event tap, input-monitoring permission or clipboard polling. Text-field snapshots can exist in memory for correction and recent Undo. Turning the feature off detaches observation.

Optional context uses Apple's on-device Foundation Models API on eligible systems. Clear deterministic corrections do not wait for model output. Low-power and serious thermal conditions disable optional inference. The app does not download slang feeds or learn from other people's messages.

Language settings, enabled-app identifiers, custom language profiles, explicitly kept words and learned rejection preferences are stored locally. The UI can forget those preferences. A user-requested diagnostic export contains version, permission state and setting counts, not typed text, saved words, app names or clipboard contents. Nothing is sent automatically.

The website edits only the current textarea. Typed text and correction history stay in the tab and are cleared when leaving; there is no application storage or network request for writing. Static hosting may receive ordinary HTTP access metadata. The public hosting service is separate from the local correction engine.

No software can identify every sensitive field or third-party editor behavior. Unsupported, password and single-line fields are deliberately skipped by the Mac integration. Use invented examples for bug reports.

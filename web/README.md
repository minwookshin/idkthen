# Browser preview

Run `npm test`, `npm run build` and `npm run dev` from this directory. The development server binds to localhost:4173. No npm install step or external service is needed.

`dist/` is the checked static output. `content-pages.json` and `build-content.mjs` generate the help, privacy, release and download pages. The typing engine and homepage are authored directly in `dist/`.

Corrections are local to the textarea. `editor-transactions.js` uses a native `insertText` edit so Undo/Redo history survives. It intentionally uses the deprecated browser editing command because direct `.value` assignment clears native history and there is no equivalent universally supported textarea transaction API. Input-triggered replacements run on the next task, with text/caret/focus checks, so Safari finishes its current typing transaction first. Unsupported editing leaves the text unchanged. Verify behavior in real browsers after changing this code; fake DOM tests alone do not prove Undo integration.

The download button is fail-closed: a verified manifest must name the expected same-origin versioned archive, a SHA-256 and notarized status. The current development manifest exposes no download.

See [MDN on execCommand and Undo history](https://developer.mozilla.org/en-US/docs/Web/API/Document/execCommand). The website is a bounded demonstration, not native OS compatibility evidence.

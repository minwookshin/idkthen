// Native edit commands are intentionally limited to this textarea. Unlike assigning value,
// the browser edit command keeps automatic corrections in native Undo/Redo.
// There is no clipboard access or HTML insertion. If unsupported, keep the text.
export function replaceWithHistory(editor, {before, start, end, text, selectionStart, selectionEnd=selectionStart}) {
  if(editor.value!==before || !Number.isInteger(start) || !Number.isInteger(end) || start<0 || end<start || end>before.length) return false;
  const expected=before.slice(0,start)+text+before.slice(end);
  if(selectionStart<0 || selectionEnd<selectionStart || selectionEnd>expected.length || typeof editor.ownerDocument.execCommand!=='function') return false;
  const oldStart=editor.selectionStart,oldEnd=editor.selectionEnd,scrollTop=editor.scrollTop;
  editor.focus({preventScroll:true});editor.setSelectionRange(start,end);
  try { editor.ownerDocument.execCommand('insertText',false,text); } catch { /* Unsupported: preserve writing. */ }
  const applied=editor.value===expected;
  if(applied) editor.setSelectionRange(selectionStart,selectionEnd);
  else if(editor.value===before) editor.setSelectionRange(oldStart,oldEnd);
  editor.scrollTop=scrollTop;
  return applied;
}

// Native Undo may restore a correction after undoing subsequent typing first.
// Match the original surrounding text; unrelated history edits do not teach Keep.
export function restoredByHistory(text, record) {
  if(!record || text.length<record.before.length) return false;
  const caret=record.caret+record.before.length-record.after.length;
  return text.startsWith(record.before.slice(0,caret)) && text.endsWith(record.before.slice(caret));
}

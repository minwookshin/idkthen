import {replaceWithHistory,restoredByHistory} from './editor-transactions.js';
import {languages,selectLanguages,lastProposal,applyProposal,recover,canAutoInput,prepareExample} from './demo-engine.js';
const $=id=>document.getElementById(id);
const editor=$('typing-area'), settings=$('typing-settings');
let selected=['es','ko'], mode='automatic', pending=null, recovery=null, composing=false, replacingSelection=false;
let programmaticEdit=false,proposalTimer=0;
const correctionHistory=[];
function editWithHistory(change){
  programmaticEdit=true;
  try{return replaceWithHistory(editor,change);}finally{programmaticEdit=false;replacingSelection=false;}
}
const linkedLanguages=selectLanguages((new URLSearchParams(location.search).get('languages')||'').split(','));
if(linkedLanguages.length) selected=linkedLanguages;
// Only untouched demonstration text may be replaced by another example.
let ownedText=editor.value;
let fittedText=null,fitFrame=0;
const kept=new Set();
const say=text=>{if($('demo-status').textContent!==text) $('demo-status').textContent=text;};
const phrases={es:'See you manana',fr:'À bientot',ko:'chromedptj',pt:'coracao',de:'strasse',it:'perche',ru:'ghbdtn',uk:'ghbdsn'};
function clearPending(){clearTimeout(proposalTimer);proposalTimer=0;pending=null; $('suggestions').replaceChildren();}
function fitEditor(force=false){
  if(!force&&fittedText===editor.value)return;
  fittedText=editor.value;
  cancelAnimationFrame(fitFrame);
  fitFrame=requestAnimationFrame(()=>{
    // Grow with a short conversation, then scroll for longer writing.
    // One measurement per frame; the correction itself never waits for it.
    const scrollTop=editor.scrollTop;
    editor.style.height='auto';
    const needed=Math.ceil(editor.scrollHeight)+2;
    editor.style.height=Math.min(260,needed)+'px';
    editor.scrollTop=needed<=260?0:scrollTop;
  });
}
function refreshControls(){
  fitEditor();
  const canUndo=!!recover(editor.value,editor.selectionStart,editor.selectionEnd,recovery);
  $('undo').disabled=!canUndo; $('undo').hidden=!canUndo;
  const preview=editor.value+' ';
  $('try-example').hidden=ownedText!==editor.value || !lastProposal(preview,preview.length,selected,kept);
  $('clear').disabled=!editor.value;
}
function flash(){
  $('demo-status').classList.remove('correction-flash');
  // Two frames keep this optional visual cue separate from the synchronous correction.
  requestAnimationFrame(()=>requestAnimationFrame(()=>$('demo-status').classList.add('correction-flash')));
}
$('demo-status').addEventListener('animationend',()=>$('demo-status').classList.remove('correction-flash'));
function apply(choice){
  if (!pending) return;
  if(editor.selectionStart!==pending.caret || editor.selectionEnd!==pending.caret){clearPending();say('The cursor moved. Try another word.');refreshControls();return;}
  const original=pending.word, before=editor.value;
  const result=applyProposal(before,pending,choice,editor.selectionStart);
  if (!result) { clearPending();say('The text changed. Try another word.');refreshControls();return; }
  if(!editWithHistory({before,start:pending.start,end:pending.end,text:choice,selectionStart:result.caret})){
    clearPending();say('This browser could not apply an undoable edit. Your text was kept.');refreshControls();return;
  }
  recovery=result.recovery;correctionHistory.push(recovery);
  if(correctionHistory.length>64)correctionHistory.shift();
  if(ownedText===before) ownedText=result.text;
  clearPending();refreshControls();say(`${original} → ${choice}`);flash();
}
function propose(){
  clearPending();pending=lastProposal(editor.value,editor.selectionStart,selected,kept);
  if (!pending) {say('Kept as typed.');refreshControls();return;}
  pending.caret=editor.selectionStart;
  if(mode==='automatic' && pending.automatic){apply(pending.choices[0].text);return;}
  say('Which reading did you mean?');
  for(const item of pending.choices){
    const button=document.createElement('button');button.type='button';button.className='choice';
    button.textContent=`${item.text} · ${item.language.toUpperCase()}`;
    button.addEventListener('click',()=>{apply(item.text);editor.focus();});$('suggestions').append(button);
  }
  const keep=document.createElement('button');keep.type='button';keep.className='quiet-button';keep.textContent='Keep original';
  keep.addEventListener('click',()=>{kept.add(pending.word.toLowerCase());clearPending();say('Kept for this session.');refreshControls();editor.focus();});$('suggestions').append(keep);
  refreshControls();
}
function completeExample(){
  if(ownedText!==editor.value || !editor.value || editor.value.length>=4000) return;
  const before=editor.value;
  if(!editWithHistory({before,start:before.length,end:before.length,text:' ',selectionStart:before.length+1}))return;
  ownedText=editor.value;
  propose();editor.focus();
}
function undo(){
  const before=editor.value,result=recover(before,editor.selectionStart,editor.selectionEnd,recovery);
  if(!result){recovery=null;refreshControls();return;}
  const record=recovery;
  if(!editWithHistory({before,start:record.start,end:record.end,text:record.word,selectionStart:result.start,selectionEnd:result.end})){
    say('This browser could not restore an undoable edit.');refreshControls();return;
  }
  kept.add(record.word.toLowerCase());
  if(ownedText===before) ownedText=result.text;
  recovery=null;clearPending();refreshControls();say('Restored. This spelling stays unchanged until Clear.');editor.focus();
}
function renderLanguages(){
  const box=$('language-options');box.replaceChildren();
  for(const language of languages){
    const button=document.createElement('button');button.type='button';button.className='language';button.dataset.language=language.id;
    const on=selected.includes(language.id);button.setAttribute('aria-pressed',String(on));
    button.disabled=(!on && selected.length>=3)||(on && selected.length===1);
    button.textContent=language.name;button.title=language.native;
    button.addEventListener('click',()=>{
      selected=selectLanguages(on?selected.filter(x=>x!==language.id):[...selected,language.id]);
      clearPending();renderLanguages();say('Languages updated. Your text is unchanged.');refreshControls();
      box.querySelector(`[data-language="${language.id}"]`)?.focus();
    });box.append(button);
  }
  $('language-count').textContent=`${selected.length+1} of 4 languages`;
  $('active-languages').textContent=['EN',...selected.map(x=>x.toUpperCase())].join(' + ');
  $('uk-note').hidden=!selected.includes('uk');
  const examples=$('examples');examples.replaceChildren();
  for(const language of languages.filter(l=>selected.includes(l.id))){
    const button=document.createElement('button');button.type='button';button.className='example';
    button.textContent=language.native;button.setAttribute('aria-label',`Try ${language.name} example`);
    button.addEventListener('click',()=>{
      const result=prepareExample(editor.value,phrases[language.id],ownedText);
      if(!result){say('The demo holds 4,000 characters. Clear some text first.');return;}
      const before=editor.value;
      if(!editWithHistory({before,start:0,end:before.length,text:result.text,selectionStart:result.text.length})){
        say('This browser could not insert an undoable example.');return;
      }
      clearPending();recovery=null;ownedText=result.replaced?result.text:null;
      // Explicit example clicks run the real bounded demo engine. They never simulate OS input.
      propose();editor.focus();
    });examples.append(button);
  }
}
editor.addEventListener('compositionstart',()=>{composing=true;ownedText=null;clearPending();refreshControls();});
editor.addEventListener('compositionend',()=>{composing=false;refreshControls();});
editor.addEventListener('beforeinput',()=>{if(!programmaticEdit)replacingSelection=editor.selectionStart!==editor.selectionEnd;});
editor.addEventListener('input',event=>{
  if(programmaticEdit)return;
  if(event.inputType==='historyUndo'){
    for(const record of correctionHistory)if(restoredByHistory(editor.value,record))kept.add(record.word.toLowerCase());
  }
  if(event.inputType==='historyUndo'||event.inputType==='historyRedo'){
    recovery=[...correctionHistory].reverse().find(record=>recover(editor.value,editor.selectionStart,editor.selectionEnd,record))||null;
    say(event.inputType==='historyUndo'?'Undone.':'Redone.');
  }
  const hadPending=!!pending,replacedSelection=replacingSelection;
  replacingSelection=false;
  ownedText=null;clearPending();refreshControls();
  if(canAutoInput({inputType:event.inputType,data:event.data,isComposing:event.isComposing,selectionStart:editor.selectionStart,selectionEnd:editor.selectionEnd,replacedSelection},composing)) {
    // Finish the browser's current native typing transaction before replacing.
    // Nested edits in Safari otherwise join the word's original Undo entry.
    const text=editor.value,caret=editor.selectionStart;
    proposalTimer=setTimeout(()=>{
      proposalTimer=0;
      if(!composing && document.activeElement===editor && editor.value===text && editor.selectionStart===caret && editor.selectionEnd===caret)propose();
    },0);
  }
  else if(event.inputType==='insertFromPaste') say('Pasted text stays as typed.');
  else if(hadPending) say('Keep typing.');
});
editor.addEventListener('keydown',event=>{
  if(event.key==='Escape'){clearPending();say('Suggestion dismissed.');}
});
function selectionChanged(){
  if(programmaticEdit)return;
  if(pending && (editor.selectionStart!==pending.caret || editor.selectionEnd!==pending.caret)){clearPending();say('Keep typing.');}
  refreshControls();
}
editor.addEventListener('select',selectionChanged);editor.addEventListener('click',selectionChanged);
editor.addEventListener('keyup',event=>{if(/^(Arrow|Home$|End$|PageUp$|PageDown$)/.test(event.key)) selectionChanged();});
document.addEventListener('selectionchange',()=>{if(document.activeElement===editor) selectionChanged();});
$('undo').addEventListener('click',undo);
$('try-example').addEventListener('click',completeExample);
$('clear').addEventListener('click',()=>{editor.value='';ownedText=null;recovery=null;correctionHistory.length=0;kept.clear();clearPending();refreshControls();say('Your words go here. Finish a word with Space.');editor.focus();});
$('open-settings').addEventListener('click',()=>settings.showModal());
$('close-settings').addEventListener('click',()=>settings.close());
settings.addEventListener('close',()=>$('open-settings').focus());
// Keep Tab within the modal even in WebViews whose native dialog traversal
// reaches browser chrome. Radio groups contribute their checked item only.
settings.addEventListener('keydown',event=>{
  if(event.key!=='Tab') return;
  const targets=[...settings.querySelectorAll('button:not(:disabled),input:checked')];
  const first=targets[0],last=targets[targets.length-1];
  if(event.shiftKey && document.activeElement===first){event.preventDefault();last.focus();}
  else if(!event.shiftKey && document.activeElement===last){event.preventDefault();first.focus();}
});
settings.addEventListener('click',event=>{if(event.target===settings){const r=settings.getBoundingClientRect();if(event.clientX<r.left||event.clientX>r.right||event.clientY<r.top||event.clientY>r.bottom) settings.close();}});
document.querySelectorAll('[name="mode"]').forEach(input=>input.addEventListener('change',()=>{
  mode=input.value;clearPending();$('mode-label').textContent=mode==='suggest'?'Suggest':'Automatic';
  say(mode==='suggest'?'Every correction waits for you.':'Clear corrections apply after Space.');refreshControls();
}));
window.addEventListener('resize',()=>fitEditor(true));
window.addEventListener('pagehide',()=>{cancelAnimationFrame(fitFrame);editor.value='';ownedText=null;recovery=null;correctionHistory.length=0;kept.clear();clearPending();say('Your words go here. Finish a word with Space.');refreshControls();});
renderLanguages();refreshControls();

import test from 'node:test';
import assert from 'node:assert/strict';
import {replaceWithHistory,restoredByHistory} from '../dist/editor-transactions.js';
import {lastProposal,applyProposal} from '../dist/demo-engine.js';

function field(value,behavior='edit') {
  const e={value,selectionStart:value.length,selectionEnd:value.length,scrollTop:42,
    focus(){},setSelectionRange(start,end){this.selectionStart=start;this.selectionEnd=end;}};
  e.ownerDocument={execCommand(command,ui,text){
    assert.equal(command,'insertText');assert.equal(ui,false);
    if(behavior==='throw')throw Error('Unsupported');
    if(behavior==='unsupported')return false;
    e.value=e.value.slice(0,e.selectionStart)+text+e.value.slice(e.selectionEnd);return true;
  }};
  return e;
}
test('native edit changes only the requested word and preserves later text and selection',()=>{
  const e=field('Before 🚀 chromedptj next');
  const before=e.value,start=before.indexOf('chromedptj');
  assert(replaceWithHistory(e,{before,start,end:start+10,text:'chrome에서',selectionStart:before.length-2}));
  assert.equal(e.value,'Before 🚀 chrome에서 next');assert.equal(e.selectionStart,e.value.length);assert.equal(e.scrollTop,42);
});
test('unsupported native editing leaves writing and selection intact',()=>{
  for(const behavior of ['throw','unsupported']){
    const e=field('chromedptj ',behavior);
    assert.equal(replaceWithHistory(e,{before:e.value,start:0,end:10,text:'chrome에서',selectionStart:9}),false);
    assert.equal(e.value,'chromedptj ');assert.equal(e.selectionStart,11);
  }
});
test('stale snapshots and invalid ranges never issue a write',()=>{
  const e=field('New text');e.ownerDocument.execCommand=()=>{throw Error('Must not run');};
  for(const patch of [{before:'Old text'},{start:-1},{end:200},{selectionStart:200}]){
    assert.equal(replaceWithHistory(e,{before:e.value,start:0,end:3,text:'Old',selectionStart:3,...patch}),false);
    assert.equal(e.value,'New text');
  }
});
test('history rejection matches original anchors without confusing another word or suffix',()=>{
  const before='Hi 🚀 chromedptj after',caret='Hi 🚀 chromedptj '.length;
  const p=lastProposal(before,caret,['ko']),r=applyProposal(before,p,'chrome에서',caret).recovery;
  assert(restoredByHistory(before,r));assert(restoredByHistory('Hi 🚀 chromedptj next after',r));
  for(const text of ['Hi 🚀 chrome에서 after','Bye 🚀 chromedptj after','Hi 🚀 chromedptj other'])assert.equal(restoredByHistory(text,r),false);
});

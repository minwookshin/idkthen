import {scenes,resolveScene} from './walkthrough-scenes.js';
import {applyProposal,recover} from './demo-engine.js';
const $=id=>document.getElementById(id);
const motion=matchMedia('(prefers-reduced-motion: reduce)');
let index=0, text='', pending=null, recovery=null, finished=false;
let playing=false, timer=null, advance=null;
const say=message=>{$('scene-status').textContent=message;};
function cancelTimer(){clearTimeout(timer);timer=null;}
function queue(action,delay){
  advance=action;cancelTimer();
  if(playing)timer=setTimeout(()=>{timer=null;advance=null;action();},delay);
}
function controls(){
  document.body.classList.toggle('is-playing',playing);
  $('play-symbol').textContent=playing?'Ⅱ':'▶';
  $('play-label').textContent=playing?'Pause':advance?'Continue':index===3&&finished?'Replay walkthrough':'Play walkthrough';
  $('show-result').disabled=finished;
  $('scene-undo').hidden=!recovery;
}
function pause(){playing=false;cancelTimer();controls();}
function renderText(){ $('scene-text').textContent=text.trimEnd(); }
function setScene(next){
  index=next;pending=null;recovery=null;finished=false;
  text=scenes[index].lead+scenes[index].word;
  $('scene-label').textContent=scenes[index].label;
  $('scene-title').textContent=scenes[index].title;
  $('scene-description').textContent=scenes[index].description;
  $('scene-count').textContent=`0${index+1} / 04`;
  $('scene-count').setAttribute('aria-label',`Scene ${index+1} of 4`);
  document.querySelectorAll('[data-scene]').forEach(button=>button.setAttribute('aria-pressed',String(Number(button.dataset.scene)===index)));
  $('scene-choices').replaceChildren();$('boundary-key').hidden=false;
  renderText();say('Finish the word with Space.');controls();
}
function choose(replacement){
  if(!pending)return;
  const result=applyProposal(text,pending,replacement,text.length);
  if(!result)return;
  text=result.text;recovery=result.recovery;pending=null;
  $('scene-choices').replaceChildren();renderText();say(`You chose ${replacement}.`);controls();
  $('scene-undo').focus();
}
function showResult(){
  const result=resolveScene(scenes[index]);text=result.before;finished=true;
  $('boundary-key').hidden=true;
  if(result.applied){
    text=result.applied.text;recovery=result.applied.recovery;
    say(`${result.proposal.word} → ${result.proposal.choices[0].text}`);
  }else if(result.proposal){
    pending=result.proposal;say('Kept as typed. Choose only if you meant something else.');
    for(const choice of pending.choices){
      const button=document.createElement('button');button.type='button';button.className='choice';
      button.textContent=`${choice.text} · ${choice.language.toUpperCase()}`;
      button.addEventListener('click',()=>choose(choice.text));$('scene-choices').append(button);
    }
    const keep=document.createElement('button');keep.type='button';keep.className='quiet-button';keep.textContent='Keep original';
    keep.addEventListener('click',()=>{pending=null;$('scene-choices').replaceChildren();say('reunion stays exactly as typed.');$('play-demo').focus();});
    $('scene-choices').append(keep);
  }else say('Kept as typed.');
  renderText();controls();
}
function playScene(){
  setScene(index);text=scenes[index].lead;renderText();say('Typing an example…');
  let character=0;
  function typeNext(){
    if(character<scenes[index].word.length){
      text+=scenes[index].word[character++];renderText();queue(typeNext,95);
    }else queue(()=>{
      showResult();
      if(index<scenes.length-1)queue(()=>{index++;playScene();},2500);
      else {playing=false;advance=null;controls();}
    },600);
  }
  if(motion.matches){
    text=scenes[index].lead+scenes[index].word;renderText();
    queue(()=>{showResult();if(index<3)queue(()=>{index++;playScene();},2800);else{playing=false;advance=null;controls();}},700);
  }else queue(typeNext,350);
}
$('play-demo').addEventListener('click',()=>{
  if(playing){pause();return;}
  playing=true;controls();
  if(advance){const next=advance;advance=null;next();}
  else {if(finished)index=0;playScene();}
});
$('show-result').addEventListener('click',()=>{pause();advance=null;showResult();});
document.querySelectorAll('[data-scene]').forEach(button=>button.addEventListener('click',()=>{pause();advance=null;setScene(Number(button.dataset.scene));}));
$('scene-undo').addEventListener('click',()=>{
  pause();advance=null;
  const result=recover(text,text.length,text.length,recovery);
  if(!result)return;
  text=result.text;recovery=null;renderText();say('Restored to your original spelling.');controls();$('play-demo').focus();
});
// Stop work when the page is out of view. Never steal focus or resume on its own.
document.addEventListener('visibilitychange',()=>{if(document.hidden)pause();});
window.addEventListener('pagehide',pause);
motion.addEventListener('change',()=>{if(playing)pause();});
document.addEventListener('keydown',event=>{if(event.key==='Escape')pause();});
setScene(0);

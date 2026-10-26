// Browser-local recovery with authored recognition and conservative context guards.
// Separate from the native Mac dictionary and on-device model.
import {koreanCandidates,protectsLiteral} from './korean-policy.js';
import {isChatLiteral} from './conversation-policy.js';
export const languages = [
  {id:'es',name:'Spanish',native:'Español',sample:'manana',result:'mañana'},
  {id:'fr',name:'French',native:'Français',sample:'francais',result:'français'},
  {id:'ko',name:'Korean',native:'한국어',sample:'chromedptj',result:'chrome에서'},
  {id:'pt',name:'Portuguese (Brazil)',native:'Português',sample:'coracao',result:'coração'},
  {id:'de',name:'German',native:'Deutsch',sample:'strasse',result:'straße',manual:true},
  {id:'it',name:'Italian',native:'Italiano',sample:'perche',result:'perché'},
  {id:'ru',name:'Russian',native:'Русский',sample:'ghbdtn',result:'привет'},
  {id:'uk',name:'Ukrainian',native:'Українська',sample:'ghbdsn',result:'привіт',manual:true},
];
const vocabulary = {
  es:{manana:'mañana',corazon:'corazón',senor:'señor',espanol:'español',reunion:'reunión',telefono:'teléfono',tambien:'también',adios:'adiós',despues:'después',facil:'fácil',dificil:'difícil',rapido:'rápido',ultima:'última',ultimo:'último',musica:'música',proximo:'próximo',ojala:'ojalá'},
  fr:{francais:'français',bientot:'bientôt',fevrier:'février',reunion:'réunion',resume:'résumé',deja:'déjà',cafe:'café',desole:'désolé',desolee:'désolée',etre:'être',tres:'très',apres:'après'},
  pt:{amanha:'amanhã',coracao:'coração',portugues:'português',voce:'você',nao:'não',obrigacao:'obrigação',voces:'vocês',tambem:'também',otimo:'ótimo',otima:'ótima',musica:'música',rapido:'rápido',ultima:'última',ultimo:'último'},
  de:{strasse:'straße',grusse:'grüße',schoen:'schön',koennen:'können',fuer:'für',moechte:'möchte',moeglich:'möglich',natuerlich:'natürlich',spaeter:'später',frueher:'früher',zurueck:'zurück',ueber:'über'},
  it:{perche:'perché',citta:'città',piu:'più',lunedi:'lunedì',universita:'università',martedi:'martedì',mercoledi:'mercoledì',giovedi:'giovedì',venerdi:'venerdì',cosi:'così',pero:'però',gia:'già'},
  ru:{ghbdtn:'привет','cgfcb,j':'спасибо',rfr:'как',lf:'да',ctqxfc:'сейчас',pfdnhf:'завтра',gjnjv:'потом',kflyj:'ладно',ghjcnj:'просто',rhenj:'круто',gjyznyj:'понятно',rjytxyj:'конечно','hf,jnf.':'работаю'},
  uk:{ghbdsn:'привіт','lzr.e':'дякую',pfhfp:'зараз',pfdnhf:'завтра','lj,ht':'добре',rhenj:'круто'},
};
// These also have intentional readings (including English reunion). Unlike the
// native engine this preview has no system dictionary; do not imply full coverage.
const ambiguous = new Set(['reunion','resume','cafe','deja','nao','lf','rfr','tres','gia','pero','cosi','ueber']);
const known = new Set(languages.map(l=>l.id));
export function selectLanguages(ids) { return [...new Set(ids)].filter(id=>known.has(id)).slice(0,3); }
function styled(original, candidate, id) {
  if (id==='ko') return candidate;
  if (original === original.toUpperCase()) return candidate.toUpperCase();
  if (/^\p{Lu}/u.test(original)) return candidate[0].toUpperCase()+candidate.slice(1);
  return candidate;
}
export function candidatesFor(word, selected, precedingContext='') {
  if (!word || word.length>96 || /[@#/:\\\d_=`]/u.test(word)) return [];
  if (!/^[\p{L},.]+$/u.test(word) || protectsLiteral(word,precedingContext) || isChatLiteral(word,selected)) return [];
  const enabled=selectLanguages(selected),results=[];
  for (const id of enabled.filter(id=>id!=='ko')) {
    const candidate=vocabulary[id]?.[word.toLowerCase()];
    const couldBeName=/^\p{Lu}/u.test(word);
    if (typeof candidate==='string' && candidate!==word.toLowerCase()) results.push({text:styled(word,candidate,id),language:id,automatic:!ambiguous.has(word.toLowerCase()) && id!=='uk' && id!=='de' && !couldBeName});
  }
  if(enabled.includes('ko')) results.push(...koreanCandidates(word,precedingContext,results.length===0));
  return results.filter((v,i,a)=>a.findIndex(x=>x.text===v.text)===i);
}
export function lastProposal(text, caret, selected, kept = new Set()) {
  if (text.length>4000 || caret<0 || caret>text.length || !Number.isInteger(caret)) return null;
  const before=text.slice(0,caret);
  // Committed Space only, matching the Mac app. Return can submit a message.
  const match=before.match(/(?:^|\s)([^\s]+) $/u);
  if (!match) return null;
  const token=match[1],tokenStart=caret-1-token.length;
  if (/[@#/\\\d_=`]/u.test(token)) return null;
  const preceding=before.slice(0,tokenStart);
  let word=token,punctuation='',prefix='';
  let choices=candidatesFor(word,selected,preceding);
  if (!choices.length) {
    const terminal=token.match(/[.,!?;:]+$/u)?.[0]||'';
    // Period/comma can themselves be Cyrillic keyboard letters. Remove the
    // shortest valid punctuation suffix, not part of the word's layout keys.
    for(let length=Math.max(1,token.length-96);length<=terminal.length;length++){
      word=token.slice(0,-length);punctuation=token.slice(-length);
      choices=candidatesFor(word,selected,preceding);
      if(choices.length)break;
    }
    if(!choices.length && terminal){word=token.slice(0,-terminal.length);punctuation=terminal;}
  }
  // A committed Korean prefix can share a token with wrong-layout Latin keys.
  if(!choices.length && selected.includes('ko')){
    const split=word.match(/^([가-힣]+)([a-zREQTWOP]+)$/u);
    if(split){prefix=split[1];word=split[2];choices=candidatesFor(word,selected,preceding+prefix);}
  }
  if (kept.has(word.toLowerCase()) || kept.has(token.toLowerCase()) || !choices.length) return null;
  const start=tokenStart+prefix.length;
  return {start,end:start+word.length,caret,word,punctuation,choices,automatic:choices.length===1 && choices[0].automatic};
}
export function applyProposal(text, proposal, replacement, caret) {
  if (caret!==proposal.caret || text.slice(proposal.start,proposal.end)!==proposal.word || !proposal.choices.some(c=>c.text===replacement)) return null;
  const after=text.slice(0,proposal.start)+replacement+text.slice(proposal.end);
  const newCaret=caret+replacement.length-proposal.word.length;
  return {text:after,caret:newCaret,recovery:{before:text,after,caret:newCaret,word:proposal.word,start:proposal.start,end:proposal.start+replacement.length}};
}
export function recover(text, selectionStart, selectionEnd, record) {
  if (!record || text.length<record.after.length || selectionStart<0 || selectionEnd<selectionStart) return null;
  const extra=text.length-record.after.length;
  const prefix=record.after.slice(0,record.caret),suffix=record.after.slice(record.caret);
  if (!text.startsWith(prefix) || !text.endsWith(suffix)) return null;
  if ((selectionStart>record.start && selectionStart<record.end) || (selectionEnd>record.start && selectionEnd<record.end) || (selectionStart<record.end && selectionEnd>record.start)) return null;
  const inserted=text.slice(record.caret,record.caret+extra);
  const originalCaret=record.caret+record.before.length-record.after.length;
  const restored=record.before.slice(0,originalCaret)+inserted+record.before.slice(originalCaret);
  const delta=record.before.length-record.after.length;
  const remap=p=>p>=record.end?p+delta:p;
  return {text:restored,start:remap(selectionStart),end:remap(selectionEnd)};
}
export function canAutoInput({inputType,data,isComposing,selectionStart,selectionEnd,replacedSelection=false}, composing=false) {
  const boundary=inputType==='insertText' && data===' ';
  return !composing && !isComposing && !replacedSelection && boundary && selectionStart===selectionEnd;
}

// Example clicks may replace only untouched demo-owned text. User writing is
// preserved byte-for-byte and the example is appended as a separate word.
export function prepareExample(text, example, ownedText=null) {
  if (typeof text!=='string' || typeof example!=='string' || !example.trim()) return null;
  const replaced=text==='' || (ownedText!==null && text===ownedText);
  const prefix=replaced?'':text+(/\s$/u.test(text)?'':' ');
  const result=prefix+example+' ';
  return result.length<=4000 ? {text:result,replaced} : null;
}

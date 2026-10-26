import test from 'node:test';
import assert from 'node:assert/strict';
import {fromQWERTY,toQWERTY} from '../dist/hangul.js';
import {candidatesFor,lastProposal,applyProposal,recover,canAutoInput} from '../dist/demo-engine.js';
const selected=['es','ko'];
// Replay each committed character through the actual production decision function.
// Browser input/controller verification is separate, not inferred from this replay.
function type(initial,keys,enabled=selected){
  let text=initial,changes=[];
  for(const char of keys){
    text+=char;
    if(char!==' '&&char!=='\n')continue;
    const p=lastProposal(text,text.length,enabled);
    if(p?.automatic){const a=applyProposal(text,p,p.choices[0].text,text.length);text=a.text;changes.push({from:p.word,to:p.choices[0].text});}
  }
  return {text,changes};
}
test('reported Korean-English-Korean sentence recovers at each typed boundary',()=>{
  const actual=type('안녕 안녕 안녕 근데 ',"sksms wlrma i'm thinking about sj ");
  assert.equal(actual.text,"안녕 안녕 안녕 근데 나는 지금 i'm thinking about 너 ");
  assert.deepEqual(actual.changes,[{from:'sksms',to:'나는'},{from:'wlrma',to:'지금'},{from:'sj',to:'너'}]);
});
test('ordinary conversational phrases work beyond the original demo examples',()=>{
  for(const sentence of ['나는 지금 집에서 일하고 있어','오늘 회의에서 확인해볼게','내일 친구랑 같이 밥먹었어','지금 뭐하고 잇엉','키보드 입력이 이제 잘되네','고마워용 안녕하세용','학교에서는 지금 테스트하고 있어요']){
    const keys=sentence.split(' ').map(toQWERTY).join(' ')+' ';
    assert.equal(type('',keys).text,sentence+' ',sentence);
  }
});
test('standard two-set conversion covers every precomposed Hangul syllable',()=>{
  for(let value=0xac00;value<=0xd7a3;value++){
    const syllable=String.fromCodePoint(value);
    assert.equal(fromQWERTY(toQWERTY(syllable)),syllable,`U+${value.toString(16)}`);
  }
  for(const sentence of ['안녕하세요','괜찮아요','감사합니다','앉아서 읽었어요','값이 있어요','까까 뽀뽀 쐐기'])assert.equal(fromQWERTY(toQWERTY(sentence)),sentence);
  assert.equal(fromQWERTY('rkqt'),'값');assert.equal(fromQWERTY('rkqtk'),'갑사');
  assert.equal(fromQWERTY('rkqt! 👋'),'값! 👋');
});
test('English, brands, chat expressions and identifiers remain literal in Korean context',()=>{
  const words=`i'm thinking about you go to the sky for her did you know that we can do this so well soda dear god gogo nana lulu lol idk brb GitHub Chrome OpenAI SJ DKSSUD Dkssud sksms.com https://sksms @sksms #sksms sksms_foo sksms123 a@sksms.com`;
  assert.equal(type('안녕 근데 ',words+' ').text,'안녕 근데 '+words+' ');
  for(const word of words.split(' '))assert.equal(lastProposal('안녕 '+word+' ',word.length+4,selected),null,word);
});
test('existing Korean, emoji, non-Latin writing and accented language text remain unchanged',()=>{
  for(const sentence of ['안녕 나는 지금 잘 쓰고 있어','Bonjour français mañana résumé','Привет Україна 東京 hello','안녕 😀 👍🏽 가족 👨‍👩‍👧‍👦','안녕 그냥 그대로'])assert.equal(type('',sentence+' ').text,sentence+' ');
});
test('short Korean readings need recent same-line Korean context',()=>{
  assert.equal(lastProposal('sj ',3,selected).automatic,false);
  assert.equal(lastProposal('안녕 sj ',6,selected).automatic,true);
  assert.equal(lastProposal('안녕\nsj ',6,selected).automatic,false);
  const far='안녕 '+('hello '.repeat(20))+'sj ';
  assert.equal(lastProposal(far,far.length,selected).automatic,false);
  assert.equal(lastProposal('안녕 sj ','안녕 sj '.length,selected).automatic,true);
});
test('unknown composed Korean is only a choice in context and never a speculative rewrite',()=>{
  const keys=toQWERTY('몽글몽글해');
  assert.equal(lastProposal(keys+' ',keys.length+1,selected),null);
  const source='안녕 '+keys+' ',p=lastProposal(source,source.length,selected);
  assert.equal(p.choices[0].text,'몽글몽글해');assert.equal(p.automatic,false);
  assert.equal(type('안녕 ',keys+' ').text,source);
});
test('disabling Korean suppresses Korean recovery without breaking other languages',()=>{
  assert.equal(type('안녕 ',"sksms wlrma i'm thinking about sj ",['es','fr']).text,"안녕 sksms wlrma i'm thinking about sj ");
  assert.equal(type('안녕 ','manana ',['es','ko']).text,'안녕 mañana ');
  const p=lastProposal('안녕 reunion ',11,['es','fr','ko']);
  assert.deepEqual(p.choices.map(x=>x.text),['reunión','réunion']);assert.equal(p.automatic,false);
});
test('punctuation and suffixes survive correction while Enter leaves spelling unchanged',()=>{
  for(const punctuation of [',','.',':',';','!','?','?!','...']){
    const s='안녕 sksms'+punctuation+' ';
    const p=lastProposal(s,s.length,selected),a=applyProposal(s,p,'나는',s.length);
    assert.equal(a.text,'안녕 나는'+punctuation+' ');
  }
  assert.equal(type('안녕 ','sksms\nwlrma\n').text,'안녕 sksms\nwlrma\n');
  const source='안녕 sksms 다음 문장';const caret='안녕 sksms '.length;
  const a=applyProposal(source,lastProposal(source,caret,selected),'나는',caret);
  assert.equal(a.text,'안녕 나는 다음 문장');
});
test('same-token Hangul prefix and recognized English brand suffix are retained',()=>{
  for(const [input,expected] of [['안녕sksms ','안녕나는 '],['한글wlrma! ','한글지금! '],['chromedptj ','chrome에서 '],['GitHubdptjsms ','GitHub에서는 '],['OpenAIdmfh ','OpenAI으로 ']])assert.equal(type('',input).text,expected);
  assert.equal(type('안녕 ','whateverdptj ').text,'안녕 whateverdptj ');
  assert.equal(type('안녕 ','한국어thinking ').text,'안녕 한국어thinking ');
});
test('literal intent, names, inline code and fenced code override otherwise valid recovery',()=>{
  for(const before of ['닉네임은 ','문자열 그대로 ','이름은 ','type exactly ','username ','named ','`code ','```\n'])assert.equal(type(before,'sksms ').text,before+'sksms ',before);
  assert.equal(type('안녕 ','"sksms" ').text,'안녕 "sksms" ');
  assert.equal(type('안녕 ','`sksms` ').text,'안녕 `sksms` ');
});
test('undo and keep still protect restored words after the sentence fix',()=>{
  const source="안녕 나는 지금 i'm thinking about sj ",caret=source.length;
  const p=lastProposal(source,caret,selected),a=applyProposal(source,p,'너',caret);
  const later=a.text+'tomorrow 😀';
  assert.equal(recover(later,later.length,later.length,a.recovery).text,source+'tomorrow 😀');
  assert.equal(lastProposal(source,caret,selected,new Set(['sj'])),null);
  assert.equal(recover(a.text.replace('너','나'),a.caret,a.caret,a.recovery),null);
});
test('Return never triggers a last-moment correction; selection replacement and IME stay protected',()=>{
  const base={inputType:'insertText',data:' ',selectionStart:5,selectionEnd:5};
  for(const inputType of ['insertLineBreak','insertParagraph'])assert.equal(canAutoInput({...base,inputType,data:null}),false);
  assert.equal(lastProposal('chromedptj\n',11,['ko']),null);
  for(const patch of [{replacedSelection:true},{isComposing:true},{inputType:'insertCompositionText'},{inputType:'insertFromComposition'},{inputType:'insertFromPaste'},{inputType:'insertReplacementText'},{inputType:'deleteContentBackward'},{inputType:'historyUndo'},{data:'sksms '}])assert.equal(canAutoInput({...base,...patch}),false);
  assert.equal(canAutoInput({...base,inputType:'insertLineBreak'},true),false);
});
test('moving the caret invalidates a pending choice before any replacement',()=>{
  const source='sj ',p=lastProposal(source,source.length,selected);
  assert.equal(applyProposal(source,p,'너',source.length-1),null);
  assert.equal(applyProposal(source,p,'너',source.length).text,'너 ');
});

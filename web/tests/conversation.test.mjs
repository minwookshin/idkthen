import test from 'node:test';
import assert from 'node:assert/strict';
import {lastProposal,applyProposal,candidatesFor,recover,languages} from '../dist/demo-engine.js';
import {toQWERTY} from '../dist/hangul.js';
function type(text,keys,selected=['es','ko']){
  for(const key of keys){
    text+=key;
    if(key!==' '&&key!=='\n')continue;
    const proposal=lastProposal(text,text.length,selected);
    if(proposal?.automatic)text=applyProposal(text,proposal,proposal.choices[0].text,text.length).text;
  }
  return text;
}
test('reported informal sentence preserves English and the exact casual Korean spelling',()=>{
  const source='yeah i think 너는 지금 going home and 그리고 집에 rktj 이제 작업을 gkrpTwld and you will be glaema  ';
  assert.equal(type('',source),'yeah i think 너는 지금 going home and 그리고 집에 가서 이제 작업을 하겠징 and you will be 힘듬  ');
});
test('authored conversational endings generalize beyond the reported three words',()=>{
  for(const sentence of ['가서 먹구 왔엉','알겠징 좋겠넹 했어용','피곤하네 졸림 힘듬','일하는중 퇴근중 집가는중','봤지 봤징 맞지 맞징','안녕 헐 대박 개꿀 꿀잼']){
    assert.equal(type('',toQWERTY(sentence)+' '),sentence+' ',sentence);
  }
});
test('short chat and full English phrases remain literal in Korean context',()=>{
  const words="yeah i think going home and you will be rn fr tbh ngl gonna wanna gotta kinda sorta thx pls plz gg ez lol lmao idk skibidi delulu rizz sus";
  assert.equal(type('안녕 ',words+' '),'안녕 '+words+' ');
  for(const word of words.split(' '))assert.equal(candidatesFor(word,['ko'],'안녕 ' ).length,0,word);
});
const fixtures=[
  {id:'es',keys:'despues',text:'después',chat:'jajaja xd tqm porfa tmb'},
  {id:'fr',keys:'desole',text:'désolé',chat:'mdr ptdr tkt jsp bcp dsl'},
  {id:'ko',keys:'gkrpTwld',text:'하겠징',chat:'ㅋㅋ ㅎㅎ ㄱㄱ ㄱㅅ ㅇㅈ'},
  {id:'pt',keys:'tambem',text:'também',chat:'kkk rsrs vc blz vlw obg pfv'},
  {id:'de',keys:'spaeter',text:'später',chat:'lg hdl vllt ka kp jz'},
  {id:'it',keys:'mercoledi',text:'mercoledì',chat:'ahah cmq xke nn tvb grz'},
  {id:'ru',keys:'ctqxfc',text:'сейчас',chat:'лол кек спс пж щас норм'},
  {id:'uk',keys:'pfhfp',text:'зараз',chat:'лол дяк прив пліз норм'},
];
for(const f of fixtures)test(`${f.id}: expanded correction plus intentional chat, with English and Korean`,()=>{
  const selected=[...new Set([f.id,'ko'])];
  const p=lastProposal(f.keys+' ',f.keys.length+1,selected);
  assert.ok(p.choices.some(x=>x.text===f.text));
  assert.equal(applyProposal(f.keys+' ',p,f.text,f.keys.length+1).text,f.text+' ');
  assert.equal(p.automatic,!['uk','de'].includes(f.id));
  assert.equal(type('안녕 ',f.chat+' ',selected),'안녕 '+f.chat+' ');
  assert.equal(type('', 'today i am going home lol ',selected),'today i am going home lol ');
});
test('all 92 supported partner sets (two to four total languages) preserve chat and bound candidates',()=>{
  const ids=languages.map(x=>x.id),sets=[];
  for(let i=0;i<ids.length;i++){
    sets.push([ids[i]]);
    for(let j=i+1;j<ids.length;j++){
      sets.push([ids[i],ids[j]]);
      for(let k=j+1;k<ids.length;k++)sets.push([ids[i],ids[j],ids[k]]);
    }
  }
  assert.equal(sets.length,92);
  for(const selected of sets){
    for(const f of fixtures.filter(x=>selected.includes(x.id))){
      assert.equal(type('안녕 ',f.chat+' ',selected),'안녕 '+f.chat+' ',selected.join('/')+f.chat);
      const p=lastProposal(f.keys+' ',f.keys.length+1,selected);
      assert.ok(p.choices.some(x=>x.text===f.text));
      if(p.choices.length>1)assert.equal(p.automatic,false);
    }
    assert.equal(type('안녕 ',"i'm thinking about you rn lol ",selected),"안녕 i'm thinking about you rn lol ");
  }
});
test('new accent homographs and proper names wait for a choice',()=>{
  for(const [key,id] of [['tres','fr'],['pero','it'],['gia','it'],['cosi','it'],['ueber','de'],['Desole','fr'],['Rapido','es']]){
    const p=lastProposal(key+' ',key.length+1,[id]);
    assert.equal(p.automatic,false,key);assert.equal(type('',key+' ',[id]),key+' ');
  }
});
test('new Cyrillic examples follow their actual keyboard layout',()=>{
  for(const [key,text,id] of [['pfdnhf','завтра','ru'],['pfdnhf','завтра','uk'],['hf,jnf.','работаю','ru'],['lj,ht','добре','uk'],['gjyznyj','понятно','ru']]){
    const p=lastProposal(key+' ',key.length+1,[id]);
    assert.equal(p.choices[0].text,text);
  }
});
test('sentence punctuation cannot consume Cyrillic layout letters',()=>{
  for(const [keys,expected] of [['hf,jnf.!','работаю!'],['hf,jnf.?','работаю?'],['cgfcb,j!','спасибо!'],['pfdnhf...','завтра...']]){
    assert.equal(type('',keys+' ',['ru']),expected+' ');
  }
  assert.equal(type('안녕 ','sksms... ',['ko']),'안녕 나는... ');
});
test('new vocabulary obeys keep, undo, names, code and language deselection',()=>{
  const text='가서 gkrpTwld ',p=lastProposal(text,text.length,['ko']),a=applyProposal(text,p,'하겠징',text.length);
  const later=a.text+'and then';
  assert.equal(recover(later,later.length,later.length,a.recovery).text,text+'and then');
  assert.equal(lastProposal(text,text.length,['ko'],new Set(['gkrptwld'])),null);
  assert.equal(type('',text,['es']),text);
  for(const source of ['gkrpTwld.dev','@gkrpTwld','gkrpTwld_1','GKRPTWLD','"gkrpTwld"','`gkrpTwld`'])assert.equal(type('안녕 ',source+' '),'안녕 '+source+' ');
});
test('unknown slang, expressive repeats and composed Korean are never normalized',()=>{
  for(const source of ['하겠징 힘듬 귀여웡','rizzler skibidi Ohio','yesssss noooo hahahaha','jajajajaja rsrsrsrs kkkkkk','ㅋㅋㅋㅋㅠㅠ','rktj😂','gkrpTwld123','몽글몽글해'])assert.equal(type('',source+' '),source+' ');
  const unknown=toQWERTY('몽글몽글해');
  assert.equal(type('안녕 ',unknown+' '),'안녕 '+unknown+' ');
});
test('JavaScript object-property names are ordinary literal text',()=>{
  for(const id of languages.map(x=>x.id)){
    for(const word of ['constructor','Constructor','CONSTRUCTOR','toString','valueOf','hasOwnProperty']){
      assert.deepEqual(candidatesFor(word,[id],'안녕 '),[],id+': '+word);
      assert.equal(type('',word+' ',[id]),word+' ');
    }
  }
});
test('long punctuation and long Hangul prefixes stay bounded without dropping characters',()=>{
  const source='rktj'+'!'.repeat(3994)+' ';
  assert.equal(type('',source,['ko']),'가서'+'!'.repeat(3994)+' ');
  const prefix='안녕'.repeat(80);
  assert.equal(type('',prefix+'rktj! ',['ko']),prefix+'가서! ');
  const punctuation='!'.repeat(3999)+' ';
  assert.equal(type('',punctuation,['ko','ru','es']),punctuation);
});

import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,readdirSync,existsSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {languages,selectLanguages,candidatesFor,lastProposal,applyProposal,recover,canAutoInput,prepareExample} from '../dist/demo-engine.js';
import {verifiedDownload} from '../dist/release-policy.js';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'../dist');
for (const language of languages) test(`${language.name}: selected example and disabled language`,()=>{
  const p=lastProposal(language.sample+' ',language.sample.length+1,[language.id]);
  assert.ok(p?.choices.some(c=>c.text===language.result));
  assert.equal(p.automatic,!language.manual);
  assert.deepEqual(candidatesFor(language.sample,[]),[]);
});
test('language count is bounded, stable and deduplicated',()=>{
  assert.deepEqual(selectLanguages(['es','es','fake','fr','ko','it']),['es','fr','ko']);
});
test('French and Spanish conflict never auto-applies',()=>{
  const p=lastProposal('reunion ',8,['es','fr']);assert.equal(p.automatic,false);
  assert.deepEqual(p.choices.map(c=>c.text),['reunión','réunion']);
});
test('English resume stays a choice',()=>assert.equal(lastProposal('resume ',7,['fr']).automatic,false));
test('English reunion stays a choice even with only one partner language',()=>{
  for(const id of ['es','fr'])assert.equal(lastProposal('reunion ',8,[id]).automatic,false);
});
test('intentional German ASCII spelling is offered, never silently rewritten',()=>{
  for(const word of ['strasse','schoen','koennen','fuer','moechte','moeglich','natuerlich','spaeter','frueher','zurueck','ueber']){
    const proposal=lastProposal(word+' ',word.length+1,['de','ko']);
    assert.ok(proposal?.choices.length,word);
    assert.equal(proposal.automatic,false,word);
  }
});
for (const text of ['https://manana','person@manana','@manana','#manana','manana.com','/manana','manana_foo','manana123','`manana`','normal','mañana','GitHub','unknownword']) test(`preserves ${text}`,()=>assert.equal(lastProposal(text+' ',text.length+1,['es','ko','fr']),null));
test('only known mixed Korean stems and exact endings',()=>{
  assert.equal(candidatesFor('GitHubfmf',['ko'])[0].text,'GitHub를');
  assert.deepEqual(candidatesFor('whateverdptj',['ko']),[]);
});
test('punctuation retained, middle caret and following text retained',()=>{
  const text='Hi, manana! next'; const p=lastProposal(text,12,['es']);
  const a=applyProposal(text,p,'mañana',12);
  assert.equal(a.text,'Hi, mañana! next');assert.equal(a.caret,12);
});
test('undo keeps later typing and a pre-existing suffix',()=>{
  const original='chromedptj next';const p=lastProposal(original,11,['ko']);const a=applyProposal(original,p,'chrome에서',11);
  const current=a.text.slice(0,a.caret)+'hello 😀 '+a.text.slice(a.caret);
  const caret=a.caret+'hello 😀 '.length;
  const result=recover(current,caret,caret,a.recovery);
  assert.equal(result.text,'chromedptj hello 😀 next');assert.equal(result.start,11+'hello 😀 '.length);
});
test('undo refuses changed anchors or correction',()=>{
  const original='hi dkssud end';const a=applyProposal(original,lastProposal(original,10,['ko']),'안녕',10);
  assert.equal(recover(a.text.replace('hi','HI'),a.caret,a.caret,a.recovery),null);
  assert.equal(recover(a.text.replace('안녕','안뇽'),a.caret,a.caret,a.recovery),null);
  assert.equal(recover(a.text,a.recovery.start,a.recovery.end,a.recovery),null);
});
test('kept words and invalid document limits',()=>{
  assert.equal(lastProposal('manana ',7,['es'],new Set(['manana'])),null);
  assert.equal(lastProposal('a'.repeat(4001),4001,['es']),null);
  assert.equal(lastProposal('manana ',-1,['es']),null);
});
test('paste, composition, deletion and replacing selection do not trigger',()=>{
  const base={inputType:'insertText',data:' ',isComposing:false,selectionStart:7,selectionEnd:7};
  assert.ok(canAutoInput(base));
  for (const patch of [{inputType:'insertFromPaste'},{isComposing:true},{data:'manana '},{inputType:'historyUndo'},{selectionEnd:9}]) assert.equal(canAutoInput({...base,...patch}),false);
  assert.equal(canAutoInput(base,true),false);
});
test('pending proposal refuses stale content and arbitrary replacement',()=>{
  const p=lastProposal('manana ',7,['es']);assert.equal(applyProposal('banana ',p,'mañana',7),null);
  assert.equal(applyProposal('manana ',p,'other',7),null);
});
test('capitalization and Cyrillic punctuation',()=>{
  assert.equal(candidatesFor('MANANA',['es'])[0].text,'MAÑANA');
  assert.equal(candidatesFor('cgfcb,j',['ru'])[0].text,'спасибо');
});
test('download closes on missing, unsigned or unsafe metadata',()=>{
  const valid={available:true,notarized:true,channel:'verified-preview',version:'0.14.0',sha256:'a'.repeat(64),downloadURL:'https://example.com/downloads/idkthen-0.14.0.zip'};
  const site='https://example.com';
  assert.equal(verifiedDownload(valid,site),valid.downloadURL);
  assert.equal(verifiedDownload(valid),null);
  for (const value of [null,{}, {...valid,available:false},{...valid,notarized:false},{...valid,channel:'development-preview'},{...valid,sha256:'bad'},{...valid,downloadURL:'javascript:alert(1)'},{...valid,downloadURL:'https://user:secret@example.com/app.zip'}, {...valid,downloadURL:'https://another.example/downloads/idkthen-0.14.0.zip'},{...valid,downloadURL:'https://example.com/downloads/idkthen-0.15.0.zip'},{...valid,downloadURL:valid.downloadURL+'?override=true'},{...valid,downloadURL:valid.downloadURL+'#app'}]) assert.equal(verifiedDownload(value,site),null);
});
test('published release metadata stays closed or matches its local same-site ZIP',()=>{
  const manifest=JSON.parse(readFileSync(resolve(root,'release.json'),'utf8'));
  if(manifest.available!==true){assert.equal(verifiedDownload(manifest),null);return;}
  const url=new URL(verifiedDownload(manifest,'https://pairtype-preview.yeyen17.chatgpt.site'));
  assert.equal(url.origin,'https://pairtype-preview.yeyen17.chatgpt.site');
  assert.equal(url.pathname,`/downloads/idkthen-${manifest.version}.zip`);
  const archive=readFileSync(resolve(root,`downloads/idkthen-${manifest.version}.zip`));
  assert.equal(createHash('sha256').update(archive).digest('hex'),manifest.sha256);
});
test('examples replace only untouched demo text and preserve personal writing',()=>{
  assert.deepEqual(prepareExample('See you manana','chromedptj','See you manana'),{text:'chromedptj ',replaced:true});
  assert.deepEqual(prepareExample('My draft 😀','manana','See you manana'),{text:'My draft 😀 manana ',replaced:false});
  assert.deepEqual(prepareExample('A draft\n','manana'),{text:'A draft\nmanana ',replaced:false});
  assert.deepEqual(prepareExample('','manana'),{text:'manana ',replaced:true});
  assert.equal(prepareExample('a'.repeat(3998),'manana'),null);
});
test('example clicks use the same candidate, choice and undo contracts',()=>{
  const text=prepareExample('Notes:','reunion').text;
  const proposal=lastProposal(text,text.length,['es','fr']);
  assert.equal(proposal.automatic,false);
  const applied=applyProposal(text,proposal,'réunion',text.length);
  assert.equal(applied.text,'Notes: réunion ');
  assert.equal(recover(applied.text,applied.caret,applied.caret,applied.recovery).text,text);
});
test('capitalized demo words need a choice and Korean shifted keys stay literal',()=>{
  assert.equal(candidatesFor('Manana',['es'])[0].automatic,false);
  assert.equal(candidatesFor('MANANA',['es'])[0].automatic,false);
  assert.deepEqual(candidatesFor('DKSSUD',['ko']),[]);
  assert.deepEqual(candidatesFor('Dkssud',['ko']),[]);
  assert.equal(candidatesFor('Ghbdtn',['ru'])[0].text,'Привет');
});
test('static internal links resolve and no trackers or submitted forms',()=>{
  for (const file of readdirSync(root).filter(x=>x.endsWith('.html'))) {
    const html=readFileSync(resolve(root,file),'utf8');
    assert.match(html,/<html lang="en">/);assert.match(html,/name="viewport"/);assert.match(html,/Content-Security-Policy/);
    assert.doesNotMatch(html,/<form[\s>]/i);
    for (const [,url] of html.matchAll(/(?:href|src)="([^"#]+)(?:#[^"]*)?"/g)) {
      if (/^(https?:|mailto:)/.test(url)) continue;
      const path=decodeURIComponent(new URL(url,'https://pairtype.example/').pathname).slice(1)||'index.html';
      assert.ok(existsSync(resolve(root,path)),`${file}: ${url}`);
    }
  }
  const app=readFileSync(resolve(root,'app.js'),'utf8');
  assert.doesNotMatch(app,/\b(fetch|XMLHttpRequest|WebSocket|sendBeacon|localStorage|sessionStorage)\b/);
});

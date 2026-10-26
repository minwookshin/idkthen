import test from 'node:test';
import assert from 'node:assert/strict';
import {scenes,demoLanguages,resolveScene} from '../dist/walkthrough-scenes.js';
import {applyProposal,recover} from '../dist/demo-engine.js';

test('showcase examples use the current engine with four languages enabled',()=>{
  assert.equal(demoLanguages.length+1,4);
  const expected=['See you mañana ','À bientôt ','chrome에서 '];
  scenes.slice(0,3).forEach((scene,i)=>{
    const result=resolveScene(scene);
    assert.ok(result.proposal.automatic);
    assert.equal(result.applied.text,expected[i]);
    assert.equal(recover(result.applied.text,result.applied.caret,result.applied.caret,result.applied.recovery).text,result.before);
  });
});
test('four-language ambiguity never chooses a language during playback',()=>{
  const result=resolveScene(scenes[3]);
  assert.equal(result.before,'reunion ');
  assert.equal(result.applied,null);
  assert.equal(result.proposal.automatic,false);
  assert.deepEqual(result.proposal.choices.map(c=>c.text),['reunión','réunion']);
  for(const choice of result.proposal.choices){
    const selected=applyProposal(result.before,result.proposal,choice.text,result.before.length);
    assert.equal(selected.text,choice.text+' ');
    assert.equal(recover(selected.text,selected.caret,selected.caret,selected.recovery).text,result.before);
  }
});
test('a disabled language cannot produce its showcase result',()=>{
  for(const [i,without] of [[0,['fr','ko']],[1,['es','ko']],[2,['es','fr']]]){
    assert.equal(resolveScene(scenes[i],without).applied,null);
  }
});

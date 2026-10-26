import test from 'node:test';
import assert from 'node:assert/strict';
import {lastProposal,applyProposal} from '../dist/demo-engine.js';

function type(text,selected) {
  let value='';
  for(const character of text) {
    value+=character;
    const proposal=lastProposal(value,value.length,selected);
    if(proposal?.automatic) value=applyProposal(value,proposal,proposal.choices[0].text,value.length).text;
  }
  return value;
}
test('bounded French and Portuguese accent examples match the native fast path',()=>{
  for(const [input,expected,language] of [
    ['Je suis deja arrive. ','Je suis déjà arrivé. ','fr'],
    ['Il habite pres de l’ecole. ','Il habite près de l’école. ','fr'],
    ['A reuniao e amanha. ','A reunião e amanhã. ','pt'],
    ['Nous sommes enfin arrives. ','Nous sommes enfin arrivés. ','fr'],
    ['O encontro será amanha. ','O encontro será amanhã. ','pt'],
  ]) assert.equal(type(input,[language]),expected);
});
test('dictionary ambiguity, names, new sentences and literal text stay untouched',()=>{
  for(const input of ['We arrive ','J’arrive ','Elle arrive ','deja ','Ask Deja ','Je suis Deja ','Je suis. arrive ','Je suis\narrive ','"Je suis arrive" ','Les pres ','Il habite. pres ']) assert.equal(type(input,['fr']),input);
  for(const input of ['Ele amanha ','amanha ','Ela amanha a terra ']) assert.equal(type(input,['pt']),input);
  assert.equal(type('Je suis deja ',['es','fr']),'Je suis deja ');
});

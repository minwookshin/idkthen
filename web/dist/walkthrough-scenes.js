import {lastProposal,applyProposal} from './demo-engine.js';

// Authored examples. Every result below is computed by the browser preview's
// existing correction rules; no canned replacement is rendered by the player.
export const demoLanguages = ['es','fr','ko'];
export const scenes = [
  {id:'spanish',label:'English + Spanish',title:'See you mañana.',lead:'See you ',word:'manana',
    description:'A missing accent. The English stays just as you wrote it.'},
  {id:'french',label:'English + French',title:'À bientôt.',lead:'À ',word:'bientot',
    description:'A quick sign-off, with the accent back in place.'},
  {id:'korean',label:'English + Korean',title:'Two languages. One word.',lead:'',word:'chromedptj',
    description:'Keep “chrome”. Recover the Korean ending typed on the wrong layout.'},
  {id:'choice',label:'When it could mean either',title:'Your words. Your call.',lead:'',word:'reunion',
    description:'English, Spanish or French? A possible reading is not a reason to guess.'},
];

export function resolveScene(scene,selected=demoLanguages) {
  const before=scene.lead+scene.word+' ';
  const proposal=lastProposal(before,before.length,selected);
  const applied=proposal?.automatic
    ? applyProposal(before,proposal,proposal.choices[0].text,before.length) : null;
  return {before,proposal,applied};
}

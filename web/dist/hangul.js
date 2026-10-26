// Independent Unicode two-set keyboard conversion, ported from idkthenCore/Hangul.swift.
// This composes exact keys; it does not rewrite Korean spelling or infer sentence meaning.
const initials=[...'ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ'];
const vowels=[...'ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ'];
const finals=[...' ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ'];
const initialKeys=['r','R','s','e','E','f','a','q','Q','t','T','d','w','W','c','z','x','v','g'];
const vowelKeys=['k','o','i','O','j','p','u','P','h','hk','ho','hl','y','n','nj','np','nl','b','m','ml','l'];
const finalKeys=['','r','R','rt','s','sw','sg','e','f','fr','fa','fq','ft','fx','fv','fg','a','q','qt','t','T','d','w','c','z','x','v','g'];
const shifted=new Set('REQTWOP');
const keys=new Map(initialKeys.map((key,i)=>[key,initials[i]]));
vowelKeys.forEach((key,i)=>{if(key.length===1) keys.set(key,vowels[i]);});
const vowelCombinations={'8,0':9,'8,1':10,'8,20':11,'13,4':14,'13,5':15,'13,20':16,'18,20':19};
const finalCombinations={'1,19':3,'4,22':5,'4,27':6,'8,1':9,'8,16':10,'8,17':11,'8,19':12,'8,25':13,'8,26':14,'8,27':15,'17,19':18};
const splitFinals={3:[1,9],5:[4,12],6:[4,18],9:[8,0],10:[8,6],11:[8,7],12:[8,9],13:[8,16],14:[8,17],15:[8,18],18:[17,9]};
export function fromQWERTY(text){
  let output='',l=null,v=null,t=0;
  function flush(){
    if(l!==null&&v!==null) output+=String.fromCodePoint(0xac00+l*588+v*28+t);
    else if(l!==null) output+=initials[l];
    else if(v!==null) output+=vowels[v];
    l=null;v=null;t=0;
  }
  for(const original of text){
    const normalized=shifted.has(original)?original:original.toLowerCase(),jamo=keys.get(normalized);
    if(!jamo){flush();output+=original;continue;}
    const nextV=vowels.indexOf(jamo);
    if(nextV!==-1){
      if(v===null){v=nextV;continue;}
      if(t>0){
        let nextL;
        if(splitFinals[t]) [t,nextL]=splitFinals[t];
        else {nextL=initials.indexOf(finals[t]);t=0;}
        flush();l=nextL;v=nextV;
      }else if(vowelCombinations[`${v},${nextV}`]!==undefined) v=vowelCombinations[`${v},${nextV}`];
      else {flush();v=nextV;}
    }else{
      const nextL=initials.indexOf(jamo),nextT=finals.indexOf(jamo);
      if(l===null&&v===null){l=nextL;continue;}
      if(l!==null&&v!==null&&nextT!==-1){
        if(t===0)t=nextT;
        else if(finalCombinations[`${t},${nextT}`]!==undefined)t=finalCombinations[`${t},${nextT}`];
        else{flush();l=nextL;}
      }else{flush();l=nextL;}
    }
  }
  flush();return output;
}
export function toQWERTY(text){
  let output='';
  for(const character of text.normalize('NFC')){
    const n=character.codePointAt(0),s=n-0xac00;
    if(s>=0&&s<11172) output+=initialKeys[Math.floor(s/588)]+vowelKeys[Math.floor(s%588/28)]+finalKeys[s%28];
    else if(initials.includes(character))output+=initialKeys[initials.indexOf(character)];
    else if(vowels.includes(character))output+=vowelKeys[vowels.indexOf(character)];
    else if(finals.includes(character)&&character!==' ')output+=finalKeys[finals.indexOf(character)];
    else output+=character;
  }
  return output;
}

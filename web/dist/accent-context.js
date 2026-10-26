// Keep these small, authored patterns aligned with native AccentContext.swift.
// They only select an existing accent candidate; no grammar rewriting or model.
export function contextualAccent(word, language, before, candidates) {
  if (word !== word.toLowerCase() || /[^\x00-\x7f]/u.test(word)) return null;
  const suffix=before.slice(-64);
  if (/["“”«»]/u.test(suffix)) return null;
  const clause=suffix.split(/[\n\r.!?;:]/u).at(-1).normalize('NFD').replace(/\p{M}/gu,'').toLowerCase().replaceAll('’',"'").replace(/[^\S\r\n]+/gu,' ');
  const auxiliary="(?:^|[^\\p{L}])(?:je suis|tu es|il est|elle est|on est|nous sommes|vous etes|ils sont|elles sont) ";
  let preferred=null;
  if(language==='fr') {
    if(word==='deja' && new RegExp(auxiliary+'$','u').test(clause)) preferred='déjà';
    if(/^arrive(?:s|e|es)?$/u.test(word) && new RegExp(auxiliary+'(?:(?:deja|bien|enfin) ){0,2}$','u').test(clause)) preferred=word.replace('arrive','arrivé');
    if(word==='pres' && /(?:^|[^\p{L}])(?:j'habite|tu habites|il habite|elle habite|on habite|nous habitons|vous habitez|ils habitent|elles habitent) (?:(?:tout|assez|tres) )?$/u.test(clause)) preferred='près';
  }
  if(language==='pt' && word==='amanha' && /(?:^|[^\p{L}])(?:a reuniao|a consulta|a festa|a viagem|a aula|o encontro|o evento|o prazo) (?:e|sera) $/u.test(clause)) preferred='amanhã';
  return candidates.includes(preferred) ? preferred : null;
}

// Small, authored chat fixtures. Preserve intentional shorthand; never expand it.
// This is a bounded local policy, not a live slang dictionary or an AI model.
const shorthand={
  en:'lol lmao lmfao rofl omg omfg btw brb afk idk ikr imo imho tbh ngl fr rn irl tldr fyi asap thx pls plz gg ez jk np nvm smh wtf wyd wya sus rizz delulu skibidi yeet fomo yolo iykyk oomf finna gonna wanna gotta kinda sorta nah yep yup yeah',
  es:'jaja jajaja jeje jajajaja jajsjaja xd xdd tkm tqm q xq pq porfa finde ntp tmb tb bn bno grax holi',
  fr:'mdr ptdr lol slt bjr bsr cc cv stp svp tkt jsp jpp prk pk pcq pq bcp ajd dsl vrm',
  pt:'kk kkk kkkk rs rsrs rsrsrs vc vcs blz vlw obg obgd pfv pq q tb tbm tmb hj amg mds tmj vdd dps flw bora',
  de:'lg vg hdl hdgdl vllt ka kp kA kP k thx pls jz trz bzw eig nh',
  it:'ahah ahaha ahahah cmq xke xche xké nn xq qnd qlc qlcs tvb tnt grz boh raga',
  ru:'лол кек рофл имхо спс пж пжл прив щас норм ок чд хз',
  uk:'лол кек імхо дяк прив пліз норм ок хз',
  ko:'ㅋㅋ ㅎㅎ ㅠㅠ ㅜㅜ ㄱㄱ ㄴㄴ ㅇㅇ ㅇㅋ ㄱㅅ ㅈㅅ ㅇㅈ ㄹㅇ ㅊㅋ',
};
const protectedWords=Object.fromEntries(Object.entries(shorthand).map(([id,words])=>[id,new Set(words.toLowerCase().split(/\s+/u))]));
export function isChatLiteral(word,selected=[]){
  const lower=word.toLowerCase();
  return ['en',...selected].some(id=>protectedWords[id]?.has(lower));
}

// Recognize only complete, authored Korean predicates plus a few common
// conversational endings. Do not strip arbitrary suffixes or fix spelling.
const predicates=`
가서 가고 가는 가면 가야 가자 갈게 갈게요 갔어 갔어요 갔는데 가겠지
와서 오고 오는 오면 와줘 왔어 왔어요 왔는데 오겠지
해서 하고 하는 하면 하자 해야 할게 할게요 했어 했어요 했지 했네 했잖아 했거든
하겠지 하겠어 하겠네 해야지 해볼게 해볼게요 해봤어 해봤지 해봤네 해도돼
먹어서 먹고 먹는 먹으면 먹자 먹었어 먹었어요 먹었지 먹었네 먹겠지 먹어야지
봐서 보고 보는 보면 보자 볼게 봤어 봤어요 봤지 봤네 보겠지
자고 자면 자자 잘게 잤어 잤어요 잤지 피곤해 피곤하네 피곤하지
알아서 알고 아는 알면 알겠지 알겠어 알겠네 알았지 알았어 알았네 모르겠지 모르겠어
좋아서 좋고 좋으면 좋겠지 좋겠어 좋겠네 좋았어 좋았지 좋았네 좋잖아
괜찮아서 괜찮고 괜찮으면 괜찮겠지 괜찮겠어 괜찮네 괜찮지
없어서 없고 없으면 없겠지 없었어 없었지 없었네
있어서 있고 있으면 있겠지 있었어 있었지 있었네 있잖아
맞아서 맞고 맞으면 맞겠지 맞았어 맞았지 맞네 맞지
돼서 되고 되면 되겠지 되겠어 되겠네 됐어 됐지 됐네
힘들어 힘들어요 힘드네 힘들지 힘들겠지 힘들었어 힘듬 힘듦
재밌어 재밌네 재밌지 재밌겠다 재밌었어 재밌음 재밌슴
웃겨 웃기네 웃기지 웃겼어 웃김 졸려 졸리네 졸림 배고픔
귀여워 귀엽네 귀엽지 귀여움 고마워 고마워요 미안해 미안해요
그렇지 그러게 그러네 그러겠지 그러니까 그래서 근데 어떻게 어떡해 어쩔
몰랐어 몰랐지 몰랐네 몰랐음 알았음 알겠음 그렇구나 그러구나 그렇군 그렇구만
했음 했슴 했당 됐음 됐당 좋음 좋당 맞음 맞슴 있음 있슴 없음 없슴 가능함
안뇽 안뇽하세요 하이루 방가 헐 대박 찐짜 진심 인정 존맛 꿀잼 노잼 개꿀
퇴근 퇴근중 출근 출근중 공부중 작업중 일하는중 생각중 쉬는중 집가는중
`.trim().split(/\s+/u);
const casual=new Set(predicates);
for(const word of predicates){
  if(word.endsWith('지'))casual.add(word.slice(0,-1)+'징');
  if(word.endsWith('네'))casual.add(word.slice(0,-1)+'넹');
  if(word.endsWith('요'))casual.add(word.slice(0,-1)+'용');
  if(word.endsWith('어'))casual.add(word.slice(0,-1)+'엉');
  if(word.endsWith('고'))casual.add(word.slice(0,-1)+'구');
}
export function recognizesKoreanConversation(word){return casual.has(word);}

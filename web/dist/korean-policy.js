import {fromQWERTY,toQWERTY} from './hangul.js';
import {recognizesKoreanConversation} from './conversation-policy.js';
// Authored conversational recognition, not a general dictionary or learned user data.
// Unknown full-syllable sequences can be offered in Korean context, never auto-applied.
const familiar=new Set(`
안녕 안녕하세요 안뇽 하이 근데 그런데 그래서 그리고 그러면 그러니까 그렇구나 그렇네
나는 너는 저는 내가 네가 제가 우리 우리는 우리가 나도 너도 저도 넌 난 너랑 나랑 너를 나를
지금 오늘 내일 어제 아까 나중에 먼저 다시 아직 이미 이제 방금 언제 어디 어디서 어디에
여기 거기 저기 여기는 거기는 어디야 여기야 거기야 집에 집에서 회사에서 학교에서
뭐하고 뭐해 뭐해요 뭐하니 뭐하는 뭐라고 뭐야 뭐지 뭔데 어떻게 왜냐면 왜냐하면
있어 있어요 있어용 잇어 잇엉 없어요 없어 없는데 있는데 있었어 있었어요 있을까 있을까요
좋아 좋아요 좋네 좋다 좋겠어 좋겠어요 싫어 싫어요 괜찮아 괜찮아요 괜찮은 고마워 고마워요 감사합니다 감사해요
미안 미안해 미안해요 죄송합니다 알겠어 알겠어요 알았어 알아 알지 몰라 모르겠어 모르겠어요
보고 보고싶어 보고싶다 생각 생각해 생각하고 생각중 생각중이야 이해 이해했어 이해했어요
하고 하는 하려고 할게 할게요 해줘 해주세요 했어 했어요 했는데 하자 하세요 해볼게 해볼게요
가능 가능해 가능해요 가능한 가능한가 될까 될까요 되는 되네 되는데 됩니다 되나요 안돼 안되네
진짜 정말 너무 많이 조금 좀더 그냥 일단 사실 혹시 아마 뭔가 이런 그런 이렇게 그렇게
맞아 맞아요 맞네 맞지 맞는 아니야 아니에요 아니 근데 그래 그래요 그러네 그럼 물론 좋아보여
먹어 먹었어 먹고 먹을까 먹었어요 밥먹었어 배고파 배고프다 맛있어 맛있다 맛있어요
잘자 잘잤어 잘했어 잘했어요 다녀올게 다녀왔어 도착 도착했어 도착했어요 출발 출발했어
할수있어 할수있어요 못하겠어 모르겠네 모르겠는데 기다려 기다려줘 잠깐 잠시
보내줘 보내주세요 보냈어 보냈어요 확인 확인해줘 확인했어 확인했어요 확인해볼게
테스트 테스트해 테스트중 테스트하고 수정 수정해줘 수정했어 수정했어요 고쳐줘 고쳤어
입력 입력하고 입력해도 바꾸면 바꾸고 바뀌네 바뀌어요 바뀌는데 그대로 문장 단어 언어
키보드 한글 한국어 영어 한국어로 영어로 안바뀌어 안바뀌네 잘되네 잘돼요 잘된다
친구 친구야 친구랑 가족 사람 사람들 이름 이름이 이름은 사용 사용자 사용하는 사용해 사용해요
회의 회의중 회의중이야 작업 작업중 작업하고 일하고 일하는 디자인 웹사이트 브라우저
시간 언제까지 얼마나 언제쯤 몇시 몇시에 내일까지 오늘까지 이번 다음 다음에 함께 같이
하하 호호 안녕하세용 고마워용 좋아용 맞아용 그래용 했어용 먹었엉 뭐하구 뭐하고있어
나는요 저는요 너는요 지금은 오늘은 내일은 어제는 여기도 거기도 이것 저것 이거 저거 그거
이걸 저걸 그걸 이게 그게 저게 이렇게는 그렇게는 사용성 빠르게 천천히 제대로
`.trim().split(/\s+/u).filter(word=>/^[가-힣]+$/u.test(word)));
const nouns=`집 학교 회사 사무실 카페 공원 병원 서울 부산 미국 캐나다 한국 친구 가족 사람 팀 회의 작업 디자인 사이트 앱 문서 파일 프로젝트 화면 키보드 컴퓨터 맥 아이폰 브라우저 시간 오늘 내일 어제 여기 거기 저기 이것 저것 그것 입력 언어 단어 문장 한글 한국어 영어 이름 사용자 사용성 도움 문제 질문 답변 내용 부분 방법 기능 오류 버전 링크 생각 마음 사진 영상 음악 날씨 음식 약속 일정 일 주말 점심 저녁 아침 커피 전화 메시지 대화 이야기 결과 설정 선택 테스트 수정 확인 준비 계획 공부 운동 영화 책 게임 돈 물 길 위치 장소 이메일 코드 버튼 화면 글 글자 앱스토어`.split(' ');
const particles=['도','만','에','에서','에게','한테','하고','까지','부터','보다','처럼','에는','에도','에서는','에서도','에서만','부터는','까지는'];
for(const noun of nouns){
  familiar.add(noun);
  const final=(noun.codePointAt(noun.length-1)-0xac00)%28;
  const endings=[...particles,final?'은':'는',final?'이':'가',final?'을':'를',final?'과':'와',final?'이랑':'랑',final?'이에요':'예요',final?'이야':'야',final&&final!==8?'으로':'로'];
  for(const ending of endings) familiar.add(noun+ending);
}
const shortWords=new Set('나 너 저 넌 난 네 내 뭘 뭐 왜 응 웅'.split(' '));
const englishProtected=new Set(`
a an the and or but if then than so as at by for from in into of off on onto out over to up with without
be am is are was were been being have has had having do does did doing done go goes going gone get gets getting got
he her hers him his she it its they them their theirs we us our ours you your yours me my mine i im ive id ill
this that these those here there where when why how what which who whom whose all any each both few more most much many
not no nor yes yet only own same such too very can could would should may might must will shall just now also even ever
never always often some someone something sometimes any anything anyone everyone everything every other another about
think thinking thought know knowing knew make making made take taking took give giving gave come coming came see seeing
saw want wanted need needed use using used work working worked say saying said tell told let lets set put keep kept
send sent write written read call called try trying tried help please thank thanks good great best better bad worse well
new old next last first second time day today tomorrow yesterday morning night people person friend family team user name
text word words type typing space enter return input output test testing tests error code value string number class function
const var import export null true false undefined default public private await async catch throw switch case break continue
app apps web website browser chrome safari firefox edge figma notion slack discord chatgpt github gitlab openai swiftui vscode
youtube gmail ai ui ux ios macos iphone ipad obsidian linear svelte nextjs vercel supabase claude llama deepseek api url html css js
lol lmao rofl skibidi rizz delulu sus yeet afaik ngl tbh idk brb imo imho fomo yolo rn ok okay hmm haha hehe gogo nana lulu
soda sky god dog cat car far ear dear gear hear near year tear fear rear
`.trim().split(/\s+/u));
const brandStems=new Set(`chrome safari firefox edge figma notion slack discord chatgpt github gitlab openai swiftui vscode youtube gmail ai ui ux ios macos iphone ipad obsidian linear svelte nextjs vercel supabase claude llama deepseek`.split(' '));
const mixedEndings=`에서부터는 으로부터는 에서부터 에서까지 에서는 에서도 에서만 에게는 에게도 으로부터 으로는 으로도 한테는 한테도 부터는 까지는 이라고 입니다 이에요 이네요 로부터 에다가 에게서 한테서 이라서 이니까 이라면 이지만 이거나 에서 에게 으로 한테 처럼 보다 부터 까지 밖에 하고 이랑 라도 로는 로도 로만 에는 에도 에만 인데 예요 라고 이고 이야 네요 만큼 은 는 이 가 을 를 의 에 로 와 과 랑 도 만`.split(' ').map(text=>({text,keys:toQWERTY(text)})).sort((a,b)=>b.keys.length-a.keys.length);
export function hasKoreanContext(before){
  const line=before.split(/[\r\n]/u).at(-1).slice(-96).normalize('NFC');
  return (line.match(/[가-힣]/gu)||[]).length>=2;
}
export function protectsLiteral(word,before=''){
  if(/^(.)\1{2,}$/iu.test(word)||/^([^aeiouy])([aeiouy])(?:\1\2){1,5}$/iu.test(word))return true;
  const recent=before.split('\n\n').at(-1).slice(-100);
  if((before.match(/`/g)||[]).length%2===1)return true;
  return /(?:\b(?:literal|verbatim|username|handle|nickname|meme|slang|named|spelling|type exactly|do not change|don't change)\b|밈|유행어|신조어|줄임말|닉네임|사용자명|문자열|그대로|바꾸지|철자|이름은|이름이)/iu.test(recent);
}
export function koreanCandidates(word,before='',allowUnknown=true){
  if(word.length>96||protectsLiteral(word,before))return [];
  const recent=hasKoreanContext(before),lower=word.toLowerCase();
  if(englishProtected.has(lower))return [];
  const mixed=[];
  for(const ending of mixedEndings){
    if(!word.endsWith(ending.keys))continue;
    const stem=word.slice(0,-ending.keys.length);
    if(brandStems.has(stem.toLowerCase()))mixed.push({text:stem+ending.text,language:'ko',automatic:ending.keys.length>2||recent});
  }
  if(mixed.length)return mixed;
  if(!/^[a-zREQTWOP]+$/.test(word)||word===word.toUpperCase())return [];
  const text=fromQWERTY(word);
  if(!/^[가-힣]+$/u.test(text)||toQWERTY(text)!==word)return [];
  const recognized=familiar.has(text)||shortWords.has(text)||recognizesKoreanConversation(text);
  const strong=text.length>=2&&word.length>=4;
  // Initial Shift can be a real double consonant (R -> ㄲ), but only an
  // authored conversational form in Korean context may bypass the name guard.
  const shiftedConversation=recent&&recognizesKoreanConversation(text)&&/^[REQTWOP]/.test(word);
  if(recognized)return [{text,language:'ko',automatic:(strong||recent)&&(!(/^[A-Z]/.test(word))||shiftedConversation)}];
  if(allowUnknown&&recent&&strong)return [{text,language:'ko',automatic:false}];
  return [];
}

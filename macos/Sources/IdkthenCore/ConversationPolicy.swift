import Foundation

/// Authored local conversation coverage shared with web v6. No network, model,
/// arbitrary suffix stripping, or expansion of deliberately informal writing.
enum ConversationPolicy {
    private static func words(_ text: String) -> Set<String> {
        Set(text.split(whereSeparator: \.isWhitespace).map(String.init))
    }
    private static let englishChat = words("lol lmao lmfao rofl omg omfg btw brb afk idk ikr imo imho tbh ngl fr rn irl tldr fyi asap thx pls plz gg ez jk np nvm smh wtf wyd wya sus rizz delulu skibidi yeet fomo yolo iykyk oomf finna gonna wanna gotta kinda sorta nah yep yup yeah")
    private static let spanishChat = words("jaja jajaja jeje jajajaja jajsjaja xd xdd tkm tqm q xq pq porfa finde ntp tmb tb bn bno grax holi")
    private static let frenchChat = words("mdr ptdr lol slt bjr bsr cc cv stp svp tkt jsp jpp prk pk pcq pq bcp ajd dsl vrm")
    private static let portugueseChat = words("kk kkk kkkk rs rsrs rsrsrs vc vcs blz vlw obg obgd pfv pq q tb tbm tmb hj amg mds tmj vdd dps flw bora")
    private static let germanChat = words("lg vg hdl hdgdl vllt ka kp ka kp k thx pls jz trz bzw eig nh")
    private static let italianChat = words("ahah ahaha ahahah cmq xke xche xké nn xq qnd qlc qlcs tvb tnt grz boh raga")
    private static let russianChat = words("лол кек рофл имхо спс пж пжл прив щас норм ок чд хз")
    private static let ukrainianChat = words("лол кек імхо дяк прив пліз норм ок хз")
    private static let koreanChat = words("ㅋㅋ ㅎㅎ ㅠㅠ ㅜㅜ ㄱㄱ ㄴㄴ ㅇㅇ ㅇㅋ ㄱㅅ ㅈㅅ ㅇㅈ ㄹㅇ ㅊㅋ")
    static func protectedWords(for partners: [LanguagePair]) -> Set<String> {
        partners.reduce(englishChat) { result, pair in
            result.union(partnerChat[pair] ?? [])
        }
    }
    static func isChatLiteral(_ word: String, pair: LanguagePair) -> Bool {
        let lower = word.lowercased().precomposedStringWithCanonicalMapping
        return englishChat.contains(lower) || partnerChat[pair]?.contains(lower) == true
    }
    private static let partnerChat: [LanguagePair: Set<String>] = [
        .spanish: spanishChat,
        .french: frenchChat,
        .portuguese: portugueseChat,
        .german: germanChat,
        .italian: italianChat,
        .russian: russianChat,
        .ukrainian: ukrainianChat,
        .korean: koreanChat
    ]
    private static let predicates = words("""
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
""")
    private static let casual: Set<String> = {
        var result = predicates
        for word in predicates {
            for (ending, replacement) in [("지", "징"), ("네", "넹"), ("요", "용"), ("어", "엉"), ("고", "구")] where word.hasSuffix(ending) {
                result.insert(String(word.dropLast()) + replacement)
            }
        }
        return result
    }()
    private static let familiar: Set<String> = {
        var result = words("""
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
""")
        let nouns = words("집 학교 회사 사무실 카페 공원 병원 서울 부산 미국 캐나다 한국 친구 가족 사람 팀 회의 작업 디자인 사이트 앱 문서 파일 프로젝트 화면 키보드 컴퓨터 맥 아이폰 브라우저 시간 오늘 내일 어제 여기 거기 저기 이것 저것 그것 입력 언어 단어 문장 한글 한국어 영어 이름 사용자 사용성 도움 문제 질문 답변 내용 부분 방법 기능 오류 버전 링크 생각 마음 사진 영상 음악 날씨 음식 약속 일정 일 주말 점심 저녁 아침 커피 전화 메시지 대화 이야기 결과 설정 선택 테스트 수정 확인 준비 계획 공부 운동 영화 책 게임 돈 물 길 위치 장소 이메일 코드 버튼 화면 글 글자 앱스토어")
        let particles = ["도","만","에","에서","에게","한테","하고","까지","부터","보다","처럼","에는","에도","에서는","에서도","에서만","부터는","까지는"]
        for noun in nouns {
            result.insert(noun)
            let final = (noun.unicodeScalars.last!.value - 0xAC00) % 28
            let endings = particles + [final > 0 ? "은" : "는", final > 0 ? "이" : "가", final > 0 ? "을" : "를", final > 0 ? "과" : "와", final > 0 ? "이랑" : "랑", final > 0 ? "이에요" : "예요", final > 0 ? "이야" : "야", final > 0 && final != 8 ? "으로" : "로"]
            for ending in endings { result.insert(noun + ending) }
        }
        // Exact laughter recovery remains available; Latin gogo/nana stay literal.
        result.formUnion(["하하하", "호호호", "있엉"])
        return result
    }()
    private static let short = words("나 너 저 넌 난 네 내 뭘 뭐 왜 응 웅")
    static func recognizesKorean(_ word: String) -> Bool {
        familiar.contains(word) || casual.contains(word) || short.contains(word)
    }
    static func koreanCandidate(for token: String, before: String, spelling: any SpellingProvider) -> String? {
        guard token.utf8.count <= 96, token != token.uppercased(),
              token.utf8.allSatisfy({ (97...122).contains($0) || [82, 69, 81, 84, 87, 79, 80].contains($0) }),
              !RecognizedVocabulary.protectedEnglish.contains(token.lowercased()),
              !isChatLiteral(token, pair: .korean), !spelling.isWord(token, language: "en") else { return nil }
        let candidate = Hangul.fromQWERTY(token)
        guard recognizesKorean(candidate), TextIdentity.matches(Hangul.toQWERTY(candidate), token) else { return nil }
        let recent = KoreanTypingContext.isRecent(before)
        // Preserve the native app's existing boundary for these informal spellings.
        if ["잇어", "잇엉", "있엉"].contains(candidate) && !recent { return nil }
        guard (candidate.count >= 2 && token.count >= 4) || recent else { return nil }
        if token.first?.isUppercase == true && !(recent && casual.contains(candidate)) { return nil }
        return candidate
    }
}

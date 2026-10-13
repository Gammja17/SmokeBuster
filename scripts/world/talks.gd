class_name Talks
extends RefCounted
## 동료들이 들려주는 대화. 조작법은 따로 "튜토리얼" 화면 없이 여기서 사람 입으로 배운다.
## 한 줄: {who, text, anim?}  선택지: {choices: [[문구, [이어질 대화]], ...]}

const INTRO := [
	{"who": "소장님", "text": "자네가 이번에 발령받은 순경인가? 반갑네. 여기 소장일세.", "anim": "wave"},
	{"who": "소장님", "text": "요즘 우리 동네 꼴이 말이 아니야. 골목마다 담배 연기, 꽁초, 낙서...", "anim": "explain"},
	{"who": "소장님", "text": "연기 피우는 사람 보이면 그 분무기로 칙칙 뿌려. [좌클릭] 이야. 물 맞으면 다들 정신 차리더군."},
	{"choices": [
		["알겠습니다!", [{"who": "소장님", "text": "좋아, 씩씩하구먼.", "anim": "laugh"}]],
		["학생이 피우면요?", [{"who": "소장님", "text": "학생한테 물 뿌리면 민원 폭탄이야. [우클릭] 으로 사진 찍어서 학교에 넘겨.", "anim": "cross_arms"}]],
	]},
	{"who": "소장님", "text": "하루 할당량 채우면 안에 들어와서 근무 일지에 퇴근 보고하고. 밤 열 시 넘으면 그냥 들어와도 돼."},
	{"who": "소장님", "text": "나머진 동료들한테 물어보게. 머리 위에 노란 표시 있는 친구가 할 말 있는 거야.", "anim": "explain"},
	{"who": "소장님", "text": "자, 나가 보게!", "anim": "salute"},
]
## 동네 사람들 부탁 (하루 한 번). 근처(radius)에서 task 를 need 번 하면 사례.
## at_door: 건물 안 사람은 그 건물 문 앞이 기준.
const FAVORS := {
	"s_vendor": {"task": "trash", "need": 5, "radius": 20.0, "pay": 120, "mental": true, "rank": 0,
		"ask": "가게 앞이 쓰레기 천지야... 근처 쓰레기 다섯 개만 주워 줘요. 떡볶이 쏠게!",
		"yes": "아이고 고마워라! 다 치우면 떡볶이 준비해 둘게~", "thanks": "떡볶이 한 접시 먹고 힘내요~ (멘탈 회복)"},
	"s_clerk": {"task": "smoke", "need": 3, "radius": 35.0, "pay": 200, "refill": true, "rank": 0, "at_door": "store",
		"ask": "가게 앞에서 담배 피우는 손님들 때문에 미치겠어요... 세 명만 쫓아 주세요!",
		"yes": "진짜요? 시원한 음료수 챙겨 둘게요!", "thanks": "덕분에 숨 좀 쉬겠어요! 음료수 가져가요~ (물 가득)"},
	"s_teacher": {"task": "teen_smoke", "need": 2, "radius": 45.0, "pay": 250, "rank": 1,
		"ask": "학교 근처에서 담배 피우는 우리 학생들... 두 명만 사진으로 남겨 주세요. 물은 안 돼요!",
		"yes": "감사합니다. 사진은 제가 잘 활용할게요.", "thanks": "덕분에 아이들 상담할 수 있겠어요. 정말 감사합니다!"},
	"s_doctor": {"task": "fight", "need": 2, "radius": 60.0, "pay": 300, "rank": 1, "at_door": "hospital",
		"ask": "요즘 싸우다 다쳐서 오는 환자가 너무 많아요. 싸움 두 건만 말려 주세요.",
		"yes": "부탁드려요. 응급실이 미어터져요.", "thanks": "오늘은 응급실이 조용하네요. 고마워요!"},
}
const MORNING := ["좋은 아침이네! 어제 수고 많았어.", "왔나? 커피는 상황실에 있네.", "오늘도 무사히 퇴근하세나.", "어제 신문 봤나? 허허, 우리 얘기더군."]


## 아침 조회: 소장님이 오늘의 특별 지시를 내린다 (첫날은 INTRO 의 마지막 인사 앞에 끼운다)
static func briefing(order: Dictionary, first_day: bool) -> Array:
	var lines: Array = []
	if first_day:
		lines = INTRO.slice(0, INTRO.size() - 1)
	else:
		lines.append({"who": "소장님", "text": MORNING.pick_random(), "anim": "wave"})
	lines.append({"who": "소장님", "text": "오늘의 특별 지시는 '%s'." % order.title, "anim": "explain"})
	lines.append({"who": "소장님", "text": order.line})
	lines.append({"who": "소장님", "text": "%d건 채우면 따로 챙겨 주지. 해당 단속은 수당도 1.5배야!" % order.goal, "anim": "cross_arms"})
	lines.append(INTRO[-1])
	return lines


const TOPICS := {
	"rookie": [
		{"who": "신입 순경", "text": "선배님! 저 하나만 알려드려도 될까요?", "anim": "salute"},
		{"who": "신입 순경", "text": "[우클릭] 하면 카메라예요. 무단횡단, 불법주차, 학생 비행은 찍어서 신고하는 거래요."},
		{"who": "신입 순경", "text": "도둑은 가방 들고 막 뛰어요. [Shift] 로 달리다가 부딪히면 태클로 잡혀요!"},
		{"choices": [
			["쓰레기는?", [{"who": "신입 순경", "text": "길에 떨어진 건 [E] 로 주우면 돼요. 동네가 조금씩 깨끗해져요."}]],
			["고마워.", []],
		]},
		{"who": "신입 순경", "text": "저도 언젠가 선배님처럼 될게요!", "anim": "salute"},
	],
	"ops": [
		{"who": "상황실 요원", "text": "상황실이에요. 신고 들어오면 무전으로 바로 보낼게요.", "anim": "talk"},
		{"who": "상황실 요원", "text": "파란 빛기둥이 출동 현장이에요. 시간 안에 가면 보너스가 붙고요."},
		{"who": "상황실 요원", "text": "그리고... 단속하다 보면 조직 단서가 나와요. 다섯 개 모이면 아지트 위치를 찾아 드릴게요.", "anim": "explain"},
	],
	"mechanic": [
		{"who": "정비 담당", "text": "어이 신입! 순찰차는 [F] 로 타. 운전하면서 [H] 누르면 사이렌.", "anim": "wave"},
		{"who": "정비 담당", "text": "물 떨어지면 빨간 소화전 옆에서 [E] 를 꾹 눌러."},
		{"who": "정비 담당", "text": "무기는 [1]~[5], 아니면 [Tab] 을 꾹 눌러서 고르고. 새 장비는 안에 사물함, 밖에선 [B] 폰 폴리스몰. 차 잃어버리면 폰으로 나 불러."},
		{"choices": [
			["불법업소는요?", [{"who": "정비 담당", "text": "물로 합선시키고 간판을 [E] 연타로 뜯어. 귀찮으면... 차로 들이받아. 히히.", "anim": "laugh"}]],
			["알겠어요.", []],
		]},
	],
}

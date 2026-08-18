# EnemyAIBehaviourTree

`EnemyAI-FSM`(그리드 A* + FSM)으로 만들었던 몬스터 AI를, Behavior Tree + Roblox 내장 NavMesh로 바꿔서 다시 만들어본 프로젝트입니다. FSM과 병행 비교하면서 "상태가 늘어나도 안 무너지는 구조"를 실제로 체감해보는 게 원래 목적이었고, 그 과정에서 겪은 애니메이션/충돌/메모리 이슈들을 하나씩 잡아나간 기록이기도 합니다.

Behavior Tree 엔진은 외부 라이브러리(BehaviorTree3 등) 없이 직접 짰습니다. Task/Sequence/Selector 세 종류 노드만 지원하는 최소 구현이고, 이유는 코드 아래쪽에 적어뒀습니다.

## 목차

- [시작하기](#시작하기)
- [프로젝트 구조](#프로젝트-구조)
- [핵심 코드 리뷰](#핵심-코드-리뷰)
  - [BehaviorTree.luau — 자체 BT 엔진](#behaviortreeluau--자체-bt-엔진)
  - [MonsterBT.luau — 실제 몬스터 행동 트리](#monsterbtluau--실제-몬스터-행동-트리)
  - [NavMeshPath.luau — 이동](#navmeshpathluau--이동)
  - [AnimationController.luau — 애니메이션](#animationcontrollerluau--애니메이션)
  - [MonsterAI.server.luau — 스폰과 최적화](#monsteraiserverluau--스폰과-최적화)
  - [기타 파일](#기타-파일)
- [알려진 한계와 트레이드오프](#알려진-한계와-트레이드오프)
- [FSM 버전과 비교하는 법](#fsm-버전과-비교하는-법)

## 시작하기

1. `Humanoid` + `HumanoidRootPart`가 있는 몬스터 모델을 `workspace.AI` 폴더 밑에 둡니다 (예: `workspace.AI.Belle`). 이름은 상관없고, 나중에 몬스터를 더 끌어다 놔도 스크립트를 안 건드려도 자동으로 AI가 붙습니다.
2. NavMesh는 따로 구울 필요 없습니다. `PathfindingService`가 런타임에 자동으로 계산하고, Studio의 `Navigation` 창은 미리보기/디버깅용일 뿐입니다.
3. `rojo serve` 켜고 Studio에서 동기화. `default.project.json`처럼 프로젝트 트리 구조 자체가 바뀌는 커밋을 받은 뒤에는 `rojo serve` 재시작 + Studio 쪽 재연결이 필요할 수 있습니다.

## 프로젝트 구조

```
src/
  shared/
    BehaviorTree.luau       -- BT 엔진 (Task/Sequence/Selector)
    MonsterBT.luau            -- 몬스터 행동 트리 정의
    NavMeshPath.luau           -- PathfindingService 래퍼 + 이벤트 기반 이동
    AnimationController.luau    -- Walk/Run/Attack 트랙 관리
    Blackboard.luau              -- 몬스터별 상태 (FSM의 타이머 필드들을 통합)
    LineOfSight.luau              -- 시야 판정 (EnemyAI-FSM 원본 그대로)
    MonsterTrail.luau              -- 이동 경로 시각화 트레일
  server/
    MonsterAI.server.luau      -- 스폰, 충돌/스크립트 최적화, 메인 루프
  starterPlayerScripts/
    SprintToggle.client.luau   -- 플레이어용 Shift 스프린트 토글
```

## 핵심 코드 리뷰

### BehaviorTree.luau — 자체 BT 엔진

Task(리프) / Sequence(전부 성공해야 성공) / Selector(하나만 성공해도 성공) 세 종류만 지원합니다. Parallel이나 Decorator는 없습니다 — 지금 트리가 그걸 요구하지 않아서 굳이 안 만들었습니다.

가장 중요한 부분은 `Run()` 끝에 있는 인터럽트 처리입니다. 매 틱 루트부터 전체를 다시 평가하는 단순한 방식이다 보니, 우선순위가 바뀌어서 어떤 Task가 이번 틱에 평가조차 안 되는 경우가 생깁니다 (예: 배회 중이던 몬스터가 플레이어를 발견해서 갑자기 추격으로 전환). 이럴 때 이전 Task의 `Finish`를 강제로 불러주지 않으면, 그 Task가 걸어놓은 이동/애니메이션이 정리되지 않고 그대로 남습니다. 실제로 이 부분을 놓쳤다가 "멈춘 채로 애니메이션만 도는" 버그를 겪었습니다.

Task 노드 객체 자체는 몬스터 100마리가 전부 같은 인스턴스를 공유합니다(`MonsterBT.luau`에서 한 번만 만들어짐). 대신 `Runtime`이 몬스터마다 따로 있어서, 같은 노드를 참조해도 상태(`Started` 여부 등)는 안 섞입니다.

### MonsterBT.luau — 실제 몬스터 행동 트리

```
Selector
├─ Sequence(체력 낮음 → Flee)          -- 최우선
├─ Sequence(시야 확보 → Pursue)         -- 추격+공격 통합
└─ Wander                              -- 기본값
```

원래 FSM 버전의 5상태(Idle/Chase/Attack/Search/Flee)를 그대로 옮기려고 했는데, `Chase`와 `Attack`을 처음엔 별도 노드로 나눴다가 다시 하나(`Pursue`)로 합쳤습니다. 사거리 경계에서 두 노드를 왔다갔다하면, 그때마다 BT 엔진의 인터럽트가 발동해서 애니메이션이 0.1초 간격으로 재시작되는 문제가 있었기 때문입니다. Task 하나 안에서 "가까우면 공격, 아니면 계속 접근"을 다 처리하니 노드 전환 자체가 없어져서 해결됐습니다.

시야 판정(`CheckLineOfSight`)에는 1초짜리 유예(`SIGHT_MEMORY`)가 있습니다. 매 틱 완전히 새로 레이캐스트를 쏘다 보니, 크라우드에 몸이 잠깐 가리거나 지형 모서리에 걸치는 한 틱짜리 오차로도 추격이 끊겼다 이어졌다 할 수 있어서, 최근 1초 안에 본 적 있으면 계속 보고 있는 걸로 칩니다.

`ApproachOffset`(Blackboard)은 몬스터마다 스폰 시 무작위로 정해지는 개인 오프셋입니다. 몬스터 여러 마리가 플레이어의 정확히 같은 좌표를 향해 걸어가면 한 점에 겹쳐 보이는데, 이동 목표 지점만 살짝 어긋나게 해서(공격 판정 거리는 그대로 실제 좌표 기준) 자연스럽게 퍼지게 만들었습니다.

### NavMeshPath.luau — 이동

`PathfindingService`로 경로를 계산하고, `MoveToFinished` 이벤트로 웨이포인트를 하나씩 따라가는 방식입니다(거리 폴링 없음). `Follow()`가 반환하는 취소 함수는 단순히 이벤트 리스너만 끊는 게 아니라, `Humanoid:MoveTo(현재 위치)`도 같이 호출합니다 — 안 그러면 우리 쪽 상태는 정리됐는데 실제 캐릭터는 마지막으로 받은 이동 명령을 향해 계속 미끄러져 가는 버그가 생깁니다.

추격(`Pursue`)만큼은 이 경로 계산을 안 씁니다. 이미 시야가 확보된 상태로 진입하는 거라, 매번 웨이포인트를 계산하고 따라가는 것보다 그냥 매 틱 플레이어 위치로 `MoveTo`를 갱신하는 게 훨씬 매끄럽고(방향이 꺾이지 않음) 쌉니다. 대신 시야가 위로는 뚫려 있어도 바닥 경로가 막힌 특이 지형에서는 벽에 헤맬 수 있다는 트레이드오프가 있습니다.

### AnimationController.luau — 애니메이션

Walk/Run/Attack 세 트랙을 관리하는 작은 클래스입니다. `typeof(setmetatable(...))` 패턴으로 `self` 타입을 잡았는데(EnemyAI-FSM에서 쓰던 것과 같은 방식), 처음엔 `new()`가 반환하는 객체에 메서드를 실제로 연결하는 걸 빼먹어서 런타임에 "그런 메서드 없음" 에러가 났었습니다. `AnimationController.__index = AnimationController` + `setmetatable`로 고쳤습니다.

몬스터 리그에 기본 `Animate` 스크립트가 딸려 있으면 이 클래스랑 같은 `Animator`를 두고 서로 애니메이션을 덮어쓰려고 경쟁합니다. `MonsterAI.server.luau`에서 모델에 붙어있는 스크립트를 전부 지우는 것도 이 때문입니다.

### MonsterAI.server.luau — 스폰과 최적화

- **스폰**: `workspace.AI`에 이미 있는 몬스터 하나를 템플릿으로 삼아 `TARGET_COUNT`까지 복제합니다. 1000~10000마리로 부하 테스트를 하면서 아래 최적화들이 붙었습니다.
- **단일 루프**: 몬스터마다 `Heartbeat` 연결을 따로 만드는 대신 전부 하나의 루프에서 처리합니다. 100개 연결이 각자 `Players:GetPlayers()`를 매 프레임 새로 호출하던 게 스터터링의 주범이었습니다.
- **거리 컬링**: 모든 플레이어로부터 200스터드 넘게 떨어진 몬스터는 레이캐스트/경로계산/BT 틱 자체를 건너뜁니다.
- **충돌 단순화**: 몬스터끼리는 충돌하지 않도록 별도 `CollisionGroup`으로 묶고, 핵심 몸통(`HumanoidRootPart`/`Torso`류) 외 파츠는 `CanCollide`를 꺼서 물리 계산량을 줄입니다. (`CollisionFidelity`도 시도했지만 일반 스크립트로는 쓸 수 없는 권한 제약이 있어서 뺐습니다.)
- **틱 분산**: 몬스터별로 시작 시점을 무작위로 어긋나게 해서, 100마리가 같은 프레임에 몰려서 계산하지 않도록 합니다.
- **트레일 개수 제한**: 트레일은 많이 겹치면 하얗게 날아가고 렌더 비용도 크므로 처음 100마리까지만 답니다.

### 기타 파일

- **`Blackboard.luau`**: 몬스터별 상태(타겟, 체력 비율, 사거리, 쿨다운 등). FSM 버전에서 개별 필드로 흩어져 있던 타이머들을 여기 한 테이블로 모았습니다.
- **`MonsterTrail.luau`**: 순수 시각 효과. `Trail` 두 `Attachment` 사이를 이어서 지나온 경로를 보여줍니다. BT/이동 로직과는 무관합니다.
- **`LineOfSight.luau`**: EnemyAI-FSM에서 그대로 가져온 원본 코드입니다. 그리드/A*와 무관한 순수 raycast라 손대지 않고 재사용했습니다.
- **`SprintToggle.client.luau`**: 플레이어용. R6는 기본 `Animate`에 "달리기"라는 개념이 없어서(속도만 빠르게 재생), Walk/Run 트랙을 직접 관리합니다. Shift로 토글.

## 알려진 한계와 트레이드오프

- **직진 추격은 지형을 안 가립니다**: `Pursue`가 NavMesh 없이 직진하기 때문에, 시야는 뚫려 있는데 바닥 경로가 막힌 지형에서는 벽에 걸릴 수 있습니다.
- **트레일은 처음 100마리까지만**: 그 이후로 스폰된 몬스터는 트레일 없이 움직입니다.
- **`ACTIVATION_RADIUS`(200)보다 먼 몬스터는 그냥 멈춰있습니다**: 실제 게임처럼 넓은 맵에 흩어져 있으면 자연스럽지만, 좁은 공간에 몰아넣고 테스트하면 어색하게 느껴질 수 있습니다.
- **`default.project.json` 구조가 바뀌는 커밋은 `rojo serve` 재시작이 필요**: 파일 내용 변경은 실시간 반영되지만, 새 서비스 매핑 추가 같은 건 재연결 전까지 반영이 안 될 수 있습니다.

## FSM 버전과 비교하는 법

같은 맵에 `EnemyAI-FSM` 몬스터와 이 프로젝트 몬스터를 나란히 두고, 발견 → 추격 → 공격 → 시야 놓침 → 배회를 재현시켜서 비교하면 됩니다.

- **이동**: 그리드 계단식 vs NavMesh 매끄러운 경로
- **디버깅**: FSM은 `GetState()` 로그 한 줄로 원인 추적이 됐지만, BT는 "지금 어느 노드가 Running인지"를 추적하는 별도 도구가 없으면 오히려 더 헤맬 수 있습니다 (이번 프로젝트에서 실제로 겪었습니다).
- **우선순위 처리**: FSM은 손으로 짠 예외 처리, BT는 최상위 Selector의 첫 번째 가지가 그 역할을 대신합니다.
- **틱당 비용**: FSM의 `if state == X`가 BT의 트리 순회보다 여전히 쌉니다. "효율적"이라는 말은 런타임 성능이 아니라 유지보수/확장성을 뜻합니다 — 몬스터 종류가 늘어날 때 그 차이가 드러납니다.

# 브랜치 전략

```
feature/*  →  dev  →  main
```

| 브랜치 | 역할 | 보호 |
|---|---|---|
| `main` | 배포 가능한 상태만. 항상 초록불 | ✅ 직접 push 금지, PR만 |
| `dev` | 통합 브랜치. 기능이 모이는 곳 | ✅ 직접 push 금지, PR만 |
| `feature/*` | 작업 브랜치. 하나의 관심사 | — |

## 흐름

```sh
# 1. dev 에서 갈라져 나온다
git switch dev && git pull
git switch -c feature/order-create-api

# 2. 작업하고 커밋
git add . && git commit -m "feat(order): 주문 생성 API"

# 3. push 하고 dev 로 PR
git push -u origin feature/order-create-api
#    → GitHub 에서 PR 생성 (base: dev)
#    → CI 통과 확인 후 머지

# 4. 기능이 쌓이면 dev → main PR
```

머지는 `--no-ff`(Create a merge commit)로 합니다. 기능 단위가 히스토리에 덩어리로 남아서
나중에 "이 기능이 언제 들어왔지"를 찾기 쉽습니다.

## 브랜치 이름

```
feature/order-create-api        기능
fix/webhook-duplicate           버그
refactor/outbox-relay           리팩터링
docs/delivery-design            문서
chore/ci-cache                  설정·잡일
```

## 커밋 메시지

```
<type>(<scope>): <내용>

feat(order): 주문 생성 API
fix(delivery): 웹훅 중복 수신 시 상태가 되돌아가는 문제
docs(adr): 0001 주문-배송 연동 방식
```

type: `feat` `fix` `refactor` `docs` `test` `chore`
scope: `order` `delivery` `infra` `adr`

## 왜 혼자 하는데 이렇게 하나

1인 저장소에 `feature → dev → main` 은 과합니다. 그럼에도 쓰는 이유:

- **CI가 걸릴 자리를 만들기 위해서.** dev PR에서 검증, main은 통과한 것만
- 회사에서 쓰는 흐름을 손에 익히기 위해서
- PR 단위로 변경을 되짚을 수 있어서 — ADR과 함께 보면 "왜 이렇게 됐나"가 남는다

번거로우면 `feature → main` 으로 줄여도 됩니다. 규칙을 지키는 것보다 계속 굴리는 게 중요합니다.

## GitHub 설정 (직접 해야 함)

Settings → Branches → Add branch ruleset

- `main`, `dev` 에 대해
- **Require a pull request before merging**
- **Require status checks to pass** → `build (order)`, `build (delivery)`

CI가 한 번 돌아야 status check 목록에 이름이 나타납니다. 첫 PR 이후에 설정하세요.

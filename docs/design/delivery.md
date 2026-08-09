# 배송 설계

## 도메인 구조

```
Order            주문번호 20260809001      ← 결제 단위. 사용자가 보는 "주문"
└── SellerOrder      작가 A                ← 송장·정산 단위. 작가가 송장을 입력하는 대상
    ├── OrderItem        작품 A1
    └── OrderItem        작품 A2
```

레벨을 나누는 기준은 **"무엇의 단위인가"** 입니다.

| 레벨 | 존재 이유 |
|---|---|
| `Order` | 결제가 한 번에 이루어지는 단위 |
| `SellerOrder` | 작가가 여럿이라 배송·정산이 갈리는 단위 |
| `OrderItem` | 취소·환불이 상품 단위로 가능해야 함 |

작가별로 따로 결제하는 구조라면 `SellerOrder`는 없어도 됩니다. 두 레벨이 있는 이유는 **결제는 하나, 작가는 여럿**이기 때문입니다.

## 상태 흐름

상태는 `SellerOrder`에만 둡니다.

```
결제대기 → 결제완료 → 배송준비중 → 배송중 → 배송완료
                          ↑          ↑         ↑
                      작가 확인   송장 입력   택배사 웹훅
```

`Order`에는 결제 여부 정도만 두고, 배송 상태는 하위 `SellerOrder`들을 나열해 보여줍니다.
상위 상태를 파생할지 저장할지 고민할 필요가 없는 이유는 **분할 배송을 지원하지 않기 때문**입니다.

## 웹훅 처리 흐름

```
택배사 웹훅 수신
  → courier_webhook_event INSERT          external_id 중복이면 여기서 끝
  → 택배사 코드 → 우리 상태로 매핑
  → status_at 이 마지막 처리분보다 과거면 무시     ← 순서 역전 방어
  → 상태가 안 바뀌었으면 끝                      ← 필터
  → 바뀌었으면 ↓ 같은 트랜잭션
        seller_order UPDATE + outbox_event INSERT
  → 릴레이가 outbox 폴링 → Kafka 발행 → published_at 갱신
```

### 왜 수신과 발신 테이블을 나누는가

택배사는 상태를 잘게 보냅니다(집화, 간선상차, 간선하차, 배송출발, 배달완료…).
반면 order에 알릴 건 두세 개뿐입니다. **수신 N건, 발신 M건, `M << N`.**

한 테이블에 `status`로 관리하면 발행하지 않기로 한 행이 계속 미처리 상태로 남아
"아직 처리 안 한 것"과 "걸러낸 것"이 구분되지 않습니다.

수신 테이블은 **append-only 로그**로 두고 처리 상태 컬럼을 넣지 않습니다.
무엇을 발행했는지는 아웃박스가 알고 있습니다.

### 멱등성이 두 겹으로 걸린다

1. `external_id` UNIQUE → 택배사가 같은 웹훅을 재전송해도 두 번 저장되지 않음
2. 상태 비교 → 같은 상태로의 중복 전이는 발행하지 않음

택배사가 배송완료를 세 번 보내도 order는 한 번만 받습니다.

### status_at 과 received_at 을 나누는 이유

웹훅은 **순서를 보장하지 않습니다.** 배송완료가 배송중보다 먼저 도착할 수 있습니다.
`received_at`(우리가 받은 시각)으로 판단하면 상태가 뒤집힙니다.
**`status_at`(택배사 기준 발생 시각)** 을 비교해 과거 이벤트면 무시해야 합니다.

Kafka에서 순서 보장이 파티션 안에서만 되는 것과 같은 문제입니다.

## 테이블

### order (order_db)

```
id
order_no          20260809001
buyer_id
total_amount
payment_status    PENDING | PAID | CANCELLED
ordered_at
```

### seller_order (order_db)

```
id
order_id          FK
seller_id         작가
status            PAYMENT_DONE | PREPARING | SHIPPING | DELIVERED
receiver_name
receiver_phone
zipcode / address / address_detail
courier_code
tracking_number
shipped_at
delivered_at
```

배송지는 **주문 시점에 확정**되므로 여기에 둡니다. 웹훅에 주소가 실려 오더라도
`payload`에 원본으로만 남기고 이 값을 정본으로 씁니다. 같은 정보를 두 곳에 저장하면 언젠가 어긋납니다.

### order_item (order_db)

```
id
seller_order_id   FK
product_id        작품
product_name      주문 시점 스냅샷
quantity
price             주문 시점 스냅샷
```

상품명·가격은 스냅샷으로 저장합니다. 나중에 작가가 가격을 바꿔도 과거 주문 내역은 그대로여야 합니다.

### courier_webhook_event (delivery_db)

```
id
external_id       UNIQUE       택배사 이벤트 고유 ID
tracking_number
courier_code
raw_status                     택배사 원본 코드
status_at                      ★ 택배사 기준 상태 발생 시각
location                       지점 / 현재 위치
driver_name                    배송기사
driver_phone
payload                        원본 JSON 통째로
received_at                    우리가 받은 시각
```

원본 payload를 통째로 남깁니다. 파싱 로직이 틀렸을 때 재처리할 수 있고,
"택배사가 진짜 이걸 보냈나" 확인이 필요할 때 근거가 됩니다.

⚠️ `driver_name` / `driver_phone` 은 개인정보입니다. 지금은 무기한 보관하지만
보관 기간과 마스킹 정책을 정해야 합니다. → ADR 필요

### outbox_event (delivery_db)

```
id
seller_order_id
event_type        SHIPMENT_REGISTERED | IN_TRANSIT | DELIVERED
payload
created_at
published_at      NULL 이면 미발행
```

`seller_order UPDATE` 와 `outbox_event INSERT` 가 **같은 트랜잭션**인 것이 핵심입니다.
상태는 바뀌었는데 이벤트가 안 나가거나, 이벤트는 나갔는데 상태가 롤백되는 상황이 사라집니다.

작가가 송장을 입력할 때도 같은 경로입니다 — 웹훅 행 없이 `seller_order UPDATE + outbox_event INSERT`.
발신 경로가 하나로 통일됩니다.

## 지금은 하지 않는 것

의도적으로 뺀 것들입니다. 필요해지면 그때 추가하고, 추가할 때 ADR을 남깁니다.

- **분할 배송** — 한 `SellerOrder`에 송장 여러 개. 지금은 1:1
  → 필요해지면 `shipment` / `shipment_item` 테이블을 빼고 `OrderItem : Shipment` 를 N:M 으로
- **수량 분할 배송** — 3개 중 2개만 먼저 출고
- **반품 / 교환**
- **인증, 결제 PG 연동, 프론트엔드, API 게이트웨이**

## 구현 순서

아웃박스를 처음부터 만들지 않습니다. **이중 쓰기 문제를 겪은 다음에** 넣습니다.

1. 인프라 기동, 토픽 생성
2. Kafka 컨슈머 그룹 동작 눈으로 확인 (콘솔 컨슈머)
3. order — 주문 생성 API
4. order → Kafka 이벤트 발행 (아웃박스 없이 직접 발행)
5. delivery — 이벤트 소비, 배송 생성
6. **여기서 이중 쓰기 문제를 만난다** → 아웃박스 도입
7. 웹훅 수신 → 상태 전이 → order 통보
8. 컨슈머 컨커런시 실험

# ecommerce-lab

이커머스 도메인을 직접 설계하면서 분산 시스템 문제를 손으로 겪어보는 연습 저장소.

**목표는 완성된 서비스가 아니라 결정의 기록입니다.** 코드는 잊어버려도 ADR은 남습니다.

> 설계 문서와 ADR은 이 저장소가 아니라 개인 Obsidian 볼트에서 관리합니다.

## 첫 목표

> 주문 생성 → Kafka 이벤트 발행 → 배송 생성

이 한 줄이 돌아가면 분산 시스템의 핵심 문제가 전부 드러납니다.

- 이벤트가 유실되면? (아웃박스 패턴)
- 중복 수신되면? (멱등성)
- 배송 생성이 실패하면 주문은? (보상 트랜잭션 / 최종 일관성)
- 순서가 뒤집히면? (파티션 키)
- 컨슈머를 늘리면? (컨커런시, 파티션 상한)

## 구조

```
ecommerce-lab/
├── services/
│   ├── order/        # 주문
│   └── delivery/     # 배송
└── infra/
    └── docker-compose.yml   # Kafka + MySQL
```

## 규칙

- **서비스는 2개로 시작.** 문제는 2개만 있어도 전부 나온다. 늘리는 건 필요해질 때
- **만들지 않는 것**: 인증, 결제 PG, 프론트엔드, API 게이트웨이, 서비스 디스커버리
  → 시간만 먹고 배우는 게 없음
- **서비스끼리 DB를 공유하지 않는다.** MySQL 인스턴스는 하나지만 스키마를 나누고,
  다른 서비스 테이블을 조인하지 않는다 (실서비스라면 인스턴스를 분리했을 자리)
- 결정을 내릴 때마다 ADR을 남긴다. 나중에 몰아 쓰면 이유를 잊는다

## 빌드

루트는 컴포지트 빌드(`includeBuild`)로 두 서비스를 묶고 있습니다.
**서비스는 여전히 독립 빌드**라 각자 `./gradlew` 도 그대로 씁니다.

```sh
# 루트에서 한 번에
./gradlew assembleAll     # 두 서비스 빌드 (테스트 제외)
./gradlew testAll         # 테스트. infra 가 떠 있어야 함
./gradlew cleanAll

# 서비스 하나만
cd services/order && ./gradlew build
```

IntelliJ 는 루트를 열면 두 프로젝트를 자동으로 잡습니다.
Settings → Build Tools → Gradle 에서 **Gradle JVM 을 21** 로 맞춰주세요.

## 인프라 띄우기

```sh
cd infra
docker compose up -d

# 토픽 생성 (파티션 6개)
docker exec ecommerce-kafka /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 --create --topic order-events --partitions 6

# 컨슈머 그룹 상태
docker exec ecommerce-kafka /opt/kafka/bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 --describe --group delivery
```

MySQL: `localhost:3306`, root / root. 스키마는 `order_db`, `delivery_db`.

## 진행

- [ ] 인프라 기동 확인
- [ ] Kafka 컨슈머 그룹 동작 눈으로 확인 (콘솔 컨슈머 2개, 그룹 다르게)
- [ ] order 서비스 — 주문 생성 API
- [ ] order → Kafka 이벤트 발행
- [ ] delivery 서비스 — 이벤트 소비, 배송 생성
- [ ] 멱등성 처리
- [ ] 아웃박스 패턴
- [ ] 컨슈머 컨커런시 실험

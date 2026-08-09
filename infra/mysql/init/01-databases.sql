-- 서비스별 스키마 분리.
-- 인스턴스는 하나지만 스키마를 나누고, 서로의 테이블을 조인하지 않는다.
-- (실서비스라면 인스턴스를 분리했을 자리 — 학습용이라 여기까지)

CREATE DATABASE IF NOT EXISTS order_db
  DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE DATABASE IF NOT EXISTS delivery_db
  DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

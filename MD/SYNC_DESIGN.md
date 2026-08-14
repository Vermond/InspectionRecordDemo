# 동기화 규칙

## 식별자
- 점검 대상과 점검 기록의 기본 식별자로 UUID를 사용한다.
- UUID는 로컬에서 최초 생성하며, 생성 이후 변경하지 않는다.
- 동일한 UUID를 서버와 로컬에서 공통 식별자로 사용한다.
- 점검 기록은 `targetID`를 통해 점검 대상의 `id`를 참조한다.
- 서버에서는 `inspection_records.target_id`가 `inspection_targets.id`를 Foreign Key로 참조한다.

## 충돌 시 우선순위
- 점검 대상과 점검 기록은 `createdAt`, `updatedAt` 값을 가진다.
- `createdAt`은 최초 생성 시각이며 이후 수정하지 않는다.
- `updatedAt`은 실제 데이터가 수정될 때마다 갱신한다.
- 서버 동기화 성공 시각으로 `updatedAt`을 변경하지 않는다.
- 동일 UUID의 서버/로컬 데이터가 모두 존재하는 경우 현재는 `updatedAt`이 더 최신인 데이터를 우선한다.
- 단, 로컬 데이터가 아직 서버에 반영되지 않은 `pending` 상태라면 서버 데이터로 덮어쓰지 않는다.
- 현재 방식은 클라이언트 시각에 의존하므로 완전한 충돌 해결 방식은 아니다.
  자세한 한계와 향후 개선 방향은 `IMPLEMENTATION.md`를 참고한다.

## 서버 중복 처리
- 서버는 Supabase PostgreSQL을 사용한다.
- `id`는 Primary Key로 사용한다.
- 서버 저장 시 동일 UUID에 대해 별도의 insert/update 분기를 두지 않고 `upsert`를 사용한다.
- 동일 UUID가 없으면 새로 생성하고, 이미 존재하면 기존 데이터를 갱신한다.
- 이 방식으로 동일 요청이 재시도되더라도 중복 record가 생성되는 것을 방지한다.

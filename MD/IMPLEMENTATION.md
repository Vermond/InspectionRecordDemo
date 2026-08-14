# 구현 범위 정리 및 후속 작업

## 1차 구현

### 점검 대상
- 점검 대상 추가/수정/조회
- SwiftData 로컬 저장
- Supabase와 UUID 기반 동기화
- 서버 fetch 후 로컬 데이터와 병합

### 점검 기록
- 점검 상태, 메모, 위치, 사진 저장
- 대상명/장비번호 snapshot 저장
- 점검 이력 목록/상세 조회
- SwiftData 로컬 저장
- Supabase `inspection_records`와 동기화
- 동일 UUID 기준 upsert

### 사진
- 카메라/사진 보관함 지원
- 사진 추가/교체/삭제
- Supabase Storage 업로드/삭제
- Edge Function `sync-inspection`에서 record와 사진 변경 처리
- 사진 변경 명령은 `keep / replace / delete` 사용

### 동기화
- 로컬 변경 시 `pending`, 성공 시 `synced`
- `pending` 로컬 데이터는 서버 데이터로 덮어쓰지 않음
- 그 외에는 `updatedAt` 기준으로 최신 데이터 병합
- `updatedAt`은 서버 동기화 시각이 아니라 실제 데이터 수정 시각
- 서버 record가 최신이어도 기존 로컬 `photoData`는 유지

---

## 현재 제한 사항

### 서버 → 로컬 사진 동기화
- 서버 fetch에서는 `photo_path`만 조회
- Storage의 사진 binary는 다운로드하지 않음
- 다른 기기/서버에서 사진이 교체·삭제되어도 로컬 `photoData`까지 자동 반영되지 않음

### 영속적 재시도
- `pending`은 미동기화 상태만 나타냄
- `photoAction` 등 당시의 동기화 작업 자체는 저장하지 않음
- 앱 종료 후 pending 작업을 완전히 복원하여 자동 재시도하는 기능은 없음

### 부분 실패
- DB와 Storage는 하나의 transaction이 아니므로 일부만 성공할 가능성이 있음
- 현재는 UUID/upsert 및 고정 Storage 경로를 이용해 재시도 시 최종 상태가 수렴하는 방향

---

## 후속 개발 시 우선 검토

### 1. 영속적 동기화 재시도
- `photoAction` 또는 별도 SyncTask/Outbox 저장
- 앱 재실행 시 pending 작업 재처리
- 네트워크 복구 후 자동 재시도

### 2. 서버 → 로컬 사진 동기화
- Storage 사진 다운로드
- 사진 변경 여부를 식별할 `photoRevision` / `photoUpdatedAt` 등 추가 검토
- 서버 사진 삭제 시 로컬 `photoData` 제거
- 로컬 사진 캐시 정책 결정

### 3. 충돌 처리 강화
현재는 `updatedAt` 기준 latest-wins 방식.
다중 기기 동시 수정까지 엄밀히 처리할 경우 server revision 또는 optimistic concurrency 도입 검토.

### 4. 삭제 동기화
점검 대상/기록 자체 삭제를 여러 기기에서 동기화할 경우
`deletedAt`, soft delete, tombstone 방식 검토.

### 5. 인증/사용자 분리
실서비스로 확장할 경우 Supabase Auth 및 사용자/조직 단위 RLS 추가.

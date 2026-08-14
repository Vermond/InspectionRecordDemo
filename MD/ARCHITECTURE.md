# Architecture

## 전체 구조

```text
SwiftUI View
    ↓
TCA Store / Feature
    ↓
Local Persistence / Network Dependency
    ├─ SwiftData
    └─ Supabase
         ├─ PostgreSQL
         ├─ Storage
         └─ Edge Function
```

- 화면 상태와 사용자 액션은 TCA Feature에서 관리한다.
- 로컬 데이터는 SwiftData에 저장한다.
- 서버 데이터는 Supabase와 동기화한다.
- 점검 기록과 사진을 함께 변경하는 작업은 Edge Function을 통해 처리한다.

## 주요 도메인

### InspectionTarget

점검 대상 정보를 나타낸다.

- 점검 대상 이름과 장비번호를 관리한다.
- 고유 UUID를 가지며 생성 이후 변경하지 않는다.
- InspectionRecord에서 해당 UUID를 참조한다.

### InspectionRecord

하나의 점검 결과를 나타낸다.

주요 데이터는 다음과 같다.

- 점검 대상 UUID
- 점검 당시 대상명/장비번호 snapshot
- 점검 상태
- 메모
- 위치
- 사진
- 생성/수정 시각
- 동기화 상태

점검 대상 정보가 이후 변경되더라도 기존 기록의 snapshot은 변경하지 않는다.

## 화면 및 Feature 구성

```text
AppFeature
└─ InspectionListFeature
    ├─ 점검 대상 관리
    ├─ 점검 기록 작성
    └─ 점검 이력 조회
```

View는 Store를 통해 State를 조회하고 Action을 전달한다.

Reducer는 Action을 처리하여 State를 변경하거나 외부 Dependency를 호출한다.

## 데이터 흐름

### 조회

```text
View 표시
→ TCA Action
→ 로컬 데이터 조회
→ 서버 데이터 fetch
→ 서버/로컬 데이터 merge
→ State 및 로컬 데이터 반영
→ View 갱신
```

서버와 로컬에 동일 UUID 데이터가 존재할 경우 `syncStatus`와 `updatedAt`을 기준으로 병합한다.

세부 규칙은 동기화 문서를 참고한다.

### 저장

```text
사용자 입력/수정
→ SwiftData 로컬 저장
→ syncStatus = pending
→ Supabase 동기화
→ 성공 시 syncStatus = synced
```

로컬 저장을 먼저 수행하므로 서버 연결 상태와 관계없이 데이터를 우선 보존할 수 있다.

### 사진을 포함한 점검 기록 저장

```text
InspectionRecord
+ photoAction
+ photoData(optional)
        ↓
sync-inspection Edge Function
        ├─ PostgreSQL
        └─ Storage
```

사진 변경 동작은 다음 세 가지로 구분한다.

- `keep`: 기존 서버 사진 유지
- `replace`: 사진 신규 업로드 또는 교체
- `delete`: 기존 사진 삭제

## 저장소 및 서버 구성

### SwiftData

- 앱의 로컬 데이터 저장
- 오프라인 상태에서도 데이터 작성 및 조회
- 서버 동기화 전 데이터 유지

### Supabase PostgreSQL

- 점검 대상 및 점검 기록 저장
- 로컬과 동일한 UUID 사용
- UUID 기준 upsert
- 점검 대상과 점검 기록 간 Foreign Key 관리

### Supabase Storage

- 점검 기록의 사진 저장
- 점검 기록 UUID를 기준으로 고정된 파일 경로 사용

### Edge Function

`sync-inspection` Edge Function이 점검 기록과 사진 변경을 처리한다.

클라이언트에서 record 정보와 사진 변경 명령을 하나의 요청으로 전달하며,
Edge Function에서 PostgreSQL과 Storage 작업을 수행한다.

## 동기화 구조

핵심 원칙은 다음과 같다.

- 서버와 로컬에서 동일 UUID를 사용한다.
- 로컬 `pending` 데이터는 서버 데이터로 덮어쓰지 않는다.
- 그 외의 동일 UUID 데이터는 `updatedAt`을 기준으로 병합한다.
- `updatedAt`은 서버 동기화 시각이 아니라 실제 데이터 수정 시각을 의미한다.
- 서버 fetch 시 사진 binary는 다운로드하지 않고 기존 로컬 `photoData`를 유지한다.

세부적인 동기화 규칙과 제한 사항은 동기화 문서를 참고한다.

## 현재 구조의 범위

현재 구조는 로컬 우선 방식의 데모 구현을 기준으로 한다.

다음 항목은 현재 범위에 포함하지 않는다.

- 서버에서 로컬로 사진 binary 다운로드
- 앱 종료 후에도 동기화 작업을 복원하는 영속적 retry / outbox
- 다중 기기 동시 수정에 대한 엄격한 충돌 처리
- 인증 및 사용자/조직 단위 데이터 분리
- 여러 기기 간 삭제 상태 동기화

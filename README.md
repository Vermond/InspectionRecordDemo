# InspectionRecordDemo

시설/장비 점검 기록을 위한 iOS 데모 앱입니다.

![InspectionRecordDemo](./RESOURCE/inspection_record_demo.gif)

## 주요 기능

- 점검 대상 등록 및 수정
- 점검 기록 작성
- 상태, 메모, 위치 정보 저장
- 카메라/사진 보관함을 통한 사진 첨부
- 점검 이력 조회
- SwiftData 기반 로컬 저장
- Supabase 서버 동기화
- 사진 업로드/교체/삭제

## 기술 스택

- Swift
- SwiftUI
- The Composable Architecture (TCA)
- SwiftData
- Supabase
  - PostgreSQL
  - Storage
  - Edge Functions

## 주요 설계

- 로컬 우선 저장
- UUID 기반 서버/로컬 공통 식별
- `pending / synced` 동기화 상태 관리
- `updatedAt` 기반 서버/로컬 데이터 병합
- 점검 대상 정보를 snapshot으로 저장하여 과거 기록 보존
- 사진 변경을 `keep / replace / delete`로 명시적으로 처리

## 프로젝트 구조

자세한 구조는 다음 문서를 참고합니다.

- [Architecture](./MD/ARCHITECTURE.md)
- [동기화 규칙](./MD/SYNC_DESIGN.md)
- [구현 범위 및 향후 개선](./MD/IMPLEMENTATION.md)

## 현재 범위

현재 버전은 데모 구현을 목표로 합니다.

서버 → 로컬 사진 다운로드, 영속적인 동기화 재시도, 다중 사용자 인증 등은 후속 범위로 두고 있습니다.

## 실행 방법

1. 프로젝트를 Clone합니다.
2. Supabase 및 관련 설정을 수행합니다. 참고: [SETUP](./SUPABASE/SETUP.md)
3. Xcode에서 프로젝트를 빌드하고 실행합니다.

민감한 Supabase 설정값은 저장소에 포함하지 않습니다.

## 개발 및 AI 활용

이 프로젝트는 개인 포트폴리오 프로젝트이며, ChatGPT와 OpenAI Codex를 적극적으로 활용하여 개발했습니다.

- 요구사항과 기능 범위 결정 및 최종 의사결정: 직접 수행
- 코드 구현 및 리팩터링: Codex 활용
- 아키텍처 및 동기화 설계: AI 제안을 참고하여 검토 및 결정
- 코드 변경 확인, 빌드, 테스트 및 실제 기기 검증: 직접 수행
- 문서 작성 및 설계 정리: AI 도움을 받아 직접 검토

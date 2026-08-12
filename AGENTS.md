//
//  AGENTS.md
//  Keysemble
//
//  Created by Jinsu Gu on 8/4/26.
//

# AGENTS.md

## 프로젝트 개요

이 프로젝트는 Swift 기반의 iOS 애플리케이션이다.

코드를 수정하기 전에 기존 프로젝트 구조, 주변 구현, naming convention, data flow를 먼저 확인한다. 새로운 패턴을 도입하기보다 기존 codebase와의 일관성을 우선한다.

## 기본 작업 절차

모든 작업은 다음 순서를 따른다.

1. 관련 파일과 call flow를 먼저 확인한다.
2. 발견한 내용과 수정 계획을 간단히 설명한다.
3. 요청에 필요한 최소 범위만 수정한다.
4. 수정 후 `git diff`를 확인한다.
5. 변경 파일, 변경 이유, 수행한 정적 검토, 사용자가 직접 확인해야 할 항목을 보고한다.

명시적으로 요청받지 않은 unrelated cleanup이나 광범위한 refactoring은 하지 않는다.

## 수정 원칙

* 요청에서 요구하지 않는 기존 동작은 변경하지 않는다.
* 큰 rewrite보다 작고 집중된 변경을 우선한다.
* 명시적인 요청 없이 public type, method, property, file, target, scheme, module 이름을 변경하지 않는다.
* public API 변경이 필요하면 먼저 영향 범위를 설명한다.
* 명시적인 요청 없이 third-party dependency를 추가하지 않는다.
* signing setting, bundle identifier, capability, entitlement, provisioning setting, deployment target을 임의로 변경하지 않는다.
* generated file은 수정하지 않는다.
* 기존 comment가 틀렸거나 변경으로 인해 더 이상 유효하지 않은 경우가 아니면 삭제하지 않는다.
* 주변 코드의 style과 convention을 따른다.
* 한 번만 사용되는 abstraction은 명확한 이점이 없는 한 추가하지 않는다.
* speculative refactoring은 하지 않는다.

## Architecture

* 수정 대상 feature에서 이미 사용 중인 architecture를 따른다.
* 가능한 경우 view rendering, business logic, state management, data access를 분리한다.
* MVVM 영역에서는 business logic과 state transition을 View에 넣지 않는다.
* hidden side effect보다 explicit data flow와 explicit state transition을 선호한다.
* global mutable state를 추가하지 않는다.
* 일부 feature에만 새로운 architecture pattern을 도입하지 않는다.
* architecture 변경이 필요하면 migration boundary와 영향 범위를 먼저 설명한다.

## Swift 규칙

* 짧거나 영리한 코드보다 명확하고 읽기 쉬운 Swift 코드를 우선한다.
* 적합한 경우 value type을 사용한다.
* invariant가 명확히 보장되지 않는 한 force unwrap과 forced cast를 피한다.
* Optional은 명시적으로 처리한다.
* actor isolation과 thread safety를 유지한다.
* Swift concurrency warning을 단순히 suppress하거나 무시하지 않는다.
* 새로운 asynchronous code는 기존 구조와 호환되는 경우 `async`/`await`와 structured concurrency를 우선한다.
* 기존 Combine, callback, GCD, `async`/`await` 코드를 단순한 style 통일 목적으로 교체하지 않는다.
* 실제 retain cycle 가능성이 있는 경우에만 `[weak self]`를 사용한다.
* 불필요한 `DispatchQueue.main.async` 호출을 추가하지 않는다.
* UI update는 MainActor 또는 main thread에서 수행한다.
* 기존 access control convention을 유지한다.

## UIKit 및 SwiftUI

* 요청에서 UI 변경을 요구하지 않는 한 기존 layout과 interaction behavior를 유지한다.
* spacing, typography, color, animation timing, accessibility identifier, navigation behavior를 임의로 변경하지 않는다.
* UIKit에서는 Auto Layout constraint와 view lifecycle을 유지한다.
* SwiftUI에서는 불필요한 state duplication과 불필요한 view invalidation을 피한다.
* 파일 수를 줄이기 위한 목적으로 logic을 View로 이동하지 않는다.
* delegate, closure, timer, NotificationCenter, asynchronous task의 retain cycle 가능성을 확인한다.

## Error handling

* error를 조용히 무시하지 않는다.
* 의미 있는 error context를 유지한다.
* 빈 `catch` block을 만들지 않는다.
* 기존 API가 요구하지 않는 한 의미 있는 error를 단순 boolean failure로 바꾸지 않는다.
* user-facing error message에 내부 구현 정보나 민감한 정보를 노출하지 않는다.

## 테스트 및 검증

이 환경에서는 build와 test를 직접 실행하지 않는다.

* `xcodebuild`, unit test, UI test를 실행하지 않는다.
* Simulator를 실행하거나 `simctl`을 사용하지 않는다.
* 실기기를 대상으로 build, install, launch, test를 시도하지 않는다.
* Xcode, CoreSimulatorService, signing, provisioning 등 로컬 개발 환경을 진단하거나 수정하지 않는다.
* 코드 변경 후에는 정적 검토와 `git diff` 확인까지만 수행한다.
* build 또는 test가 필요한 경우 사용자가 직접 실행할 수 있도록 정확한 명령이나 절차를 제시한다.
* 실제로 실행하지 않은 build나 test를 성공 또는 통과했다고 표현하지 않는다.
* 정적 검토만으로 확인할 수 없는 사항은 검증되지 않은 항목으로 명확히 보고한다.

프로젝트에 기존 build/test command가 문서화돼 있다면 사용자가 직접 실행할 명령을 제시할 때 이를 우선한다. 그렇지 않다면 `.xcworkspace`, `.xcodeproj`, scheme, target, destination을 확인하여 적절한 명령을 제안하되 직접 실행하지 않는다.

## Git 규칙

* 명시적인 요청 없이 commit, amend, merge, rebase, push, force-push, tag 생성, PR 생성을 하지 않는다.
* 기존 uncommitted change를 삭제하거나 덮어쓰지 않는다.
* 작업 시작 전에 `git status`를 확인한다.
* 작업 완료 후 `git diff`를 확인한다.
* `git reset --hard`, `git clean`, destructive restore command를 사용하지 않는다.
* 요청과 관계없는 `.gitignore` 변경을 하지 않는다.
* 하나의 작업에서 발생한 변경은 논리적으로 집중된 상태를 유지한다.
* pre-existing modification은 사용자의 작업으로 간주하고 임의로 수정하지 않는다.

## 파일 및 작업 범위

다음 항목은 직접 관련된 경우가 아니면 조사하거나 수정하지 않는다.

* `DerivedData`
* `.build`
* `build`
* `Pods`
* checked-out package build artifact
* generated source file

접근 가능하다는 이유만으로 크고 관련 없는 directory를 탐색하지 않는다.

사용자가 특정 file이나 folder를 지정했다면 그것을 기본 modification scope로 간주한다. 정확한 수정을 위해 범위 확장이 필요하다면 이유를 먼저 설명한다.

## Code review 규칙

Code review를 요청받으면 다음을 우선 확인한다.

1. 실제 defect
2. regression 가능성
3. concurrency hazard
4. lifecycle issue
5. performance issue
6. maintainability risk

각 finding에는 다음 내용을 포함한다.

* severity
* 관련 file과 symbol
* 문제가 발생하는 조건
* 실제 영향
* 수정 방향

확인된 문제와 가능성만 있는 우려를 구분한다.

리뷰 항목 수를 늘리기 위해 근거 없는 문제를 만들지 않는다.

수정 요청이 없다면 코드를 변경하지 않는다.

리뷰와 수정을 함께 요청받았다면 confirmed issue를 우선 수정하고, 광범위한 style rewrite는 피한다.

## Communication

* 설명은 직접적이고 구체적으로 작성한다.
* verified fact, inference, assumption을 구분한다.
* 안전하게 판단할 수 없는 필수 결정이 있을 때만 clarification을 요청한다.
* 사소한 ambiguity는 기존 project convention을 따른다.
* 실제 수정과 검증이 끝나기 전에는 작업이 완료됐다고 표현하지 않는다.
* 최종 보고에는 다음을 포함한다.

  * 변경 요약
  * 변경 파일
  * 수행한 정적 검토
  * 사용자가 직접 수행해야 할 build/test
  * 남은 risk
  * 검증하지 못한 항목

## 프로젝트별 정보

아래 항목을 실제 프로젝트에 맞게 채운다.

* Main application target: `<TARGET_NAME>`
* Main scheme: `<SCHEME_NAME>`
* Minimum iOS version: `<IOS_VERSION>`
* UI framework: `<UIKit / SwiftUI / Mixed>`
* Architecture: `<MVVM / MVC / Other>`
* Dependency manager: `<Swift Package Manager / CocoaPods / None>`
* Unit test target: `<TEST_TARGET_NAME>`
* Workspace or project file: `<PROJECT.xcworkspace / PROJECT.xcodeproj>`
* Preferred simulator destination: `<DEVICE_AND_OS>`

## 금지 사항 요약

* 요청 없이 commit 또는 push하지 않는다.
* 요청 없이 architecture를 변경하지 않는다.
* 요청 없이 dependency를 추가하지 않는다.
* 요청 없이 public API를 변경하지 않는다.
* 기존 사용자 변경사항을 삭제하지 않는다.
* 검증하지 않은 내용을 성공했다고 보고하지 않는다.
* 요청 범위를 넘어선 refactoring을 하지 않는다.
* 사용자가 명시적으로 요청한 defect만 수정한다.
* 요청 없이 readability, style, consistency, cleanup을 이유로 코드를 변경하지 않는다.
* 요청 없이 naming 변경, method 분리·병합, 코드 재배치, formatting 변경을 하지 않는다.
* 요청 없이  동작에 직접 필요하지 않은 refactoring은 금지한다.
* 수정 전 변경할 파일과 변경 내용을 먼저 보고하고, 사용자의 승인을 받기 전에는 편집하지 않는다.
* 요청이 "review"인 경우 파일을 절대 수정하지 않는다.
* 요청이 "review and fix"인 경우에도 confirmed defect에 필요한 최소 line만 변경한다.


## 기타
* 기본적으로는 deprecated 버전을 사용하지 않고 최신 API를 사용하도록 한다.
* TCA 사용시 1.26.1 기준의 현재 API를 사용하고 deprecated API는 사용하지 않는다.

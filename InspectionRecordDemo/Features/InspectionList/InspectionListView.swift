import ComposableArchitecture
import Foundation
import SwiftUI
import UIKit

struct InspectionListView: View {
    @Bindable var store: StoreOf<InspectionListFeature>
    @Environment(\.openURL) private var openURL

    var body: some View {
        TabView(selection: $store.selectedTab) {
            Tab(
                InspectionListFeature.State.Tab.targets.title,
                systemImage: InspectionListFeature.State.Tab.targets.systemImage,
                value: InspectionListFeature.State.Tab.targets
            ) {
                InspectionTargetsView(store: store)
            }

            Tab(
                InspectionListFeature.State.Tab.history.title,
                systemImage: InspectionListFeature.State.Tab.history.systemImage,
                value: InspectionListFeature.State.Tab.history
            ) {
                InspectionHistoryView(store: store)
            }
        }
        .sheet(
            item: $store.scope(
                state: \.destination?.targetForm,
                action: \.destination.targetForm
            )
        ) { targetStore in
            TargetFormView(store: targetStore)
        }
        .sheet(
            item: $store.scope(
                state: \.destination?.inspection,
                action: \.destination.inspection
            )
        ) { inspectionStore in
            InspectionEditorView(store: inspectionStore)
        }
        .task {
            await store.send(.task).finish()
        }
        .alert(
            store.isLocationPermissionWarningPresented ? "위치 정보 없음" : "점검 데이터 오류",
            isPresented: Binding(
                get: {
                    store.persistenceErrorMessage != nil
                        || store.isLocationPermissionWarningPresented
                },
                set: { isPresented in
                    guard !isPresented else { return }
                    if store.isLocationPermissionWarningPresented {
                        store.send(.locationPermissionWarningDismissed)
                    } else {
                        store.send(.persistenceErrorDismissed)
                    }
                }
            )
        ) {
            if store.isLocationPermissionWarningPresented {
                Button("닫기", role: .cancel) {
                    store.send(.locationPermissionWarningDismissed)
                }
                Button("다시 알리지 않기") {
                    store.send(.locationPermissionWarningSuppressionRequested)
                }
                Button("설정 열기") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                    store.send(.locationPermissionWarningSettingsButtonTapped)
                }
            } else {
                Button("확인") {
                    store.send(.persistenceErrorDismissed)
                }
            }
        } message: {
            Text(
                store.isLocationPermissionWarningPresented
                    ? "이번 점검에는 위치 정보가 기록되지 않았습니다. 위치 권한을 허용하면 다음 점검부터 위치를 기록할 수 있습니다."
                    : (store.persistenceErrorMessage ?? "점검 데이터를 처리하지 못했습니다.")
            )
        }
    }
}

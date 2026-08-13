import ComposableArchitecture
import Foundation
import SwiftUI

struct TargetDetailView: View {
    @Bindable var store: StoreOf<TargetDetailFeature>

    var body: some View {
        NavigationStack {
            Form {
                Section("점검 대상") {
                    LabeledContent("이름", value: store.target.name)
                    LabeledContent("장비번호", value: store.target.equipmentNumber)
                    LabeledContent(
                        "생성일",
                        value: store.target.createdAt.formatted(date: .abbreviated, time: .shortened)
                    )
                    LabeledContent(
                        "수정일",
                        value: store.target.updatedAt.formatted(date: .abbreviated, time: .shortened)
                    )

                    if let latestInspectionAt = store.latestInspectionAt {
                        LabeledContent(
                            "최근 점검",
                            value: latestInspectionAt.formatted(date: .abbreviated, time: .shortened)
                        )
                    }
                }
            }
            .navigationTitle("점검 대상 상세")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") {
                        store.send(.closeButtonTapped)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("수정") {
                        store.send(.editButtonTapped)
                    }
                }
            }
        }
        .sheet(
            item: $store.scope(
                state: \.destination?.targetForm,
                action: \.destination.targetForm
            )
        ) { targetFormStore in
            TargetFormView(store: targetFormStore)
        }
    }
}

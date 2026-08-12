import ComposableArchitecture
import SwiftUI

struct TargetFormView: View {
    @Bindable var store: StoreOf<TargetFormFeature>

    var body: some View {
        NavigationStack {
            Form {
                TextField("점검 대상 이름", text: $store.name)
                TextField("장비 번호", text: $store.equipmentNumber)
            }
            .navigationTitle("점검 대상 추가")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        store.send(.cancelButtonTapped)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        store.send(.saveButtonTapped)
                    }
                    .disabled(!store.canSave)
                }
            }
        }
    }
}

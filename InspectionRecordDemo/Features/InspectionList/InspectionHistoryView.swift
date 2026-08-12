import ComposableArchitecture
import Foundation
import SwiftUI

struct InspectionHistoryView: View {
    @Bindable var store: StoreOf<InspectionListFeature>

    var body: some View {
        NavigationStack {
            List {
                if store.filteredRecords.isEmpty {
                    Text(store.searchText.isEmpty ? "작성된 점검 이력이 없습니다." : "검색 결과가 없습니다.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.filteredRecords) { record in
                        Button {
                            store.send(.recordSelected(record.id))
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.targetNameSnapshot)
                                    .font(.headline)
                                Text(record.status?.title ?? "상태 미지정")
                                    .font(.subheadline)
                                Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("점검 이력")
            .searchable(text: $store.searchText, prompt: "점검 이력 검색")
        }
    }
}

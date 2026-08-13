import ComposableArchitecture
import Foundation
import SwiftUI

struct InspectionTargetsView: View {
    @Bindable var store: StoreOf<InspectionListFeature>

    var body: some View {
        NavigationStack {
            List {
                if store.targets.isEmpty {
                    Text("등록된 점검 대상이 없습니다.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.targets) { target in
                        let latestRecord = store.latestRecordsByTargetID[target.id]

                        HStack(alignment: .center, spacing: 12) {
                            Button {
                                store.send(.targetSelected(target.id))
                            } label: {
                                HStack(alignment: .center, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(target.name)
                                            .font(.headline)
                                        Text(target.equipmentNumber)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer(minLength: 12)

                                    VStack(alignment: .trailing, spacing: 4) {
                                        if let latestRecord {
                                            Text(latestRecord.status?.title ?? "상태 미지정")
                                                .font(.subheadline)
                                            Text(latestRecord.createdAt.formatted(date: .abbreviated, time: .shortened))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        } else {
                                            Text("미점검")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                            Text("기록 없음")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button {
                                store.send(.targetDetailButtonTapped(target.id))
                            } label: {
                                Image(systemName: "info.circle")
                                    .font(.title3)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("점검 대상 상세")
                        }
                    }
                }
            }
            .navigationTitle("점검 대상")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.send(.addTargetButtonTapped)
                    } label: {
                        Label("추가", systemImage: "plus")
                    }
                }
            }
        }
    }
}

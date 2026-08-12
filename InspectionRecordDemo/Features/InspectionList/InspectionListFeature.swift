import ComposableArchitecture
import Foundation
import SwiftUI

@Reducer
struct InspectionListFeature {
    @ObservableState
    struct State: Equatable {
        enum Tab: String, CaseIterable, Equatable, Hashable, Sendable {
            case targets
            case history

            var title: String {
                switch self {
                case .targets:
                    "점검 대상"
                case .history:
                    "점검 이력"
                }
            }

            var systemImage: String {
                switch self {
                case .targets:
                    "list.bullet.rectangle"
                case .history:
                    "clock.arrow.circlepath"
                }
            }
        }

        var selectedTab: Tab = .targets
        var targets: [InspectionTarget] = []
        var records: [InspectionRecord] = []
        var searchText = ""
        @Presents var destination: Destination.State?

        var filteredRecords: [InspectionRecord] {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !query.isEmpty else {
                return records
            }

            return records.filter { record in
                record.targetName.localizedCaseInsensitiveContains(query)
                    || record.equipmentNumber.localizedCaseInsensitiveContains(query)
                    || record.memo.localizedCaseInsensitiveContains(query)
                    || (record.status?.title.localizedCaseInsensitiveContains(query) ?? false)
            }
        }

        var latestRecordsByTargetID: [InspectionTarget.ID: InspectionRecord] {
            Dictionary(grouping: records, by: \.targetID)
                .compactMapValues { targetRecords in
                    targetRecords.max { $0.createdAt < $1.createdAt }
                }
        }
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case addTargetButtonTapped
        case targetSelected(InspectionTarget.ID)
        case recordSelected(InspectionRecord.ID)
        case destination(PresentationAction<Destination.Action>)
    }

    @Reducer
    enum Destination {
        case targetForm(TargetFormFeature)
        case inspection(InspectionEditorFeature)
    }

    var body: some ReducerOf<Self> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .addTargetButtonTapped:
                state.destination = .targetForm(TargetFormFeature.State())
                return .none

            case let .targetSelected(targetID):
                guard let target = state.targets.first(where: { $0.id == targetID }) else {
                    return .none
                }

                state.destination = .inspection(InspectionEditorFeature.State(target: target))
                return .none

            case let .recordSelected(recordID):
                guard let record = state.records.first(where: { $0.id == recordID }) else {
                    return .none
                }

                state.destination = .inspection(InspectionEditorFeature.State(record: record))
                return .none

            case let .destination(.presented(.targetForm(.delegate(.saved(target))))):
                state.targets.append(target)
                state.destination = nil
                return .none

            case .destination(.presented(.targetForm(.delegate(.cancelled)))):
                state.destination = nil
                return .none

            case let .destination(.presented(.inspection(.delegate(.saved(record))))):
                if let index = state.records.firstIndex(where: { $0.id == record.id }) {
                    state.records[index] = record
                } else {
                    state.records.insert(record, at: 0)
                }

                state.destination = nil
                return .none

            case .destination(.presented(.inspection(.delegate(.cancelled)))):
                state.destination = nil
                return .none

            case .destination:
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }
}

extension InspectionListFeature.Destination.State: Equatable {}

@Reducer
struct TargetFormFeature {
    @ObservableState
    struct State: Equatable {
        var name = ""
        var equipmentNumber = ""

        var canSave: Bool {
            !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !equipmentNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case saveButtonTapped
        case cancelButtonTapped
        case delegate(Delegate)

        enum Delegate: Equatable {
            case saved(InspectionTarget)
            case cancelled
        }
    }

    var body: some ReducerOf<Self> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .saveButtonTapped:
                guard state.canSave else {
                    return .none
                }

                let target = InspectionTarget(
                    id: UUID(),
                    name: state.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    equipmentNumber: state.equipmentNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                )

                return .send(.delegate(.saved(target)))

            case .cancelButtonTapped:
                return .send(.delegate(.cancelled))

            case .delegate:
                return .none
            }
        }
    }
}

struct InspectionListView: View {
    @Bindable var store: StoreOf<InspectionListFeature>

    var body: some View {
        TabView(selection: $store.selectedTab) {
            Tab(
                InspectionListFeature.State.Tab.targets.title,
                systemImage: InspectionListFeature.State.Tab.targets.systemImage,
                value: InspectionListFeature.State.Tab.targets
            ) {
                targetsView
            }
            
            Tab(
                InspectionListFeature.State.Tab.history.title,
                systemImage: InspectionListFeature.State.Tab.history.systemImage,
                value: InspectionListFeature.State.Tab.history
            ) {
                historyView
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
    }

    private var targetsView: some View {
        NavigationStack {
            List {
                if store.targets.isEmpty {
                    Text("등록된 점검 대상이 없습니다.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.targets) { target in
                        let latestRecord = store.latestRecordsByTargetID[target.id]

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

    private var historyView: some View {
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
                                Text(record.targetName)
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

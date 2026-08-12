import ComposableArchitecture
import Foundation
import PhotosUI
import SwiftUI
import UIKit

@Reducer
struct InspectionEditorFeature {
    enum Mode: Equatable, Sendable {
        case create
        case view
        case editing

        var isEditable: Bool {
            self == .create || self == .editing
        }

        var navigationTitle: String {
            switch self {
            case .create:
                "점검 작성"
            case .view, .editing:
                "점검 기록"
            }
        }
    }

    @ObservableState
    struct State: Equatable {
        struct Snapshot: Equatable {
            let photoData: Data?
            let status: InspectionStatus?
            let memo: String
        }

        let target: InspectionTarget
        let recordID: UUID?
        let createdAt: Date
        var mode: Mode
        var photoData: Data?
        var status: InspectionStatus?
        var memo: String
        var originalSnapshot: Snapshot?
        var photoErrorMessage: String?

        init(target: InspectionTarget) {
            self.target = target
            self.recordID = nil
            self.createdAt = Date()
            self.mode = .create
            self.photoData = nil
            self.status = nil
            self.memo = ""
            self.originalSnapshot = nil
            self.photoErrorMessage = nil
        }

        init(record: InspectionRecord) {
            self.target = InspectionTarget(
                id: record.targetID,
                name: record.targetName,
                equipmentNumber: record.equipmentNumber
            )
            self.recordID = record.id
            self.createdAt = record.createdAt
            self.mode = .view
            self.photoData = record.photoData
            self.status = record.status
            self.memo = record.memo
            self.originalSnapshot = nil
            self.photoErrorMessage = nil
        }

        var snapshot: Snapshot {
            Snapshot(photoData: photoData, status: status, memo: memo)
        }
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case editButtonTapped
        case closeButtonTapped
        case saveButtonTapped
        case cancelButtonTapped
        case photoDataLoaded(Data)
        case photoLoadingFailed
        case delegate(Delegate)

        enum Delegate: Equatable {
            case saved(InspectionRecord)
            case cancelled
        }
    }

    var body: some ReducerOf<Self> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .editButtonTapped:
                guard state.mode == .view else {
                    return .none
                }

                state.originalSnapshot = state.snapshot
                state.mode = .editing
                return .none

            case .closeButtonTapped:
                return .send(.delegate(.cancelled))

            case .saveButtonTapped:
                let record = InspectionRecord(
                    id: state.recordID ?? UUID(),
                    targetID: state.target.id,
                    targetName: state.target.name,
                    equipmentNumber: state.target.equipmentNumber,
                    createdAt: state.createdAt,
                    photoData: state.photoData,
                    status: state.status,
                    memo: state.memo
                )

                return .send(.delegate(.saved(record)))

            case .cancelButtonTapped:
                switch state.mode {
                case .create:
                    return .send(.delegate(.cancelled))
                case .view:
                    return .none
                case .editing:
                    if let originalSnapshot = state.originalSnapshot {
                        state.photoData = originalSnapshot.photoData
                        state.status = originalSnapshot.status
                        state.memo = originalSnapshot.memo
                    }

                    state.originalSnapshot = nil
                    state.mode = .view
                    return .none
                }

            case let .photoDataLoaded(data):
                state.photoData = data
                state.photoErrorMessage = nil
                return .none

            case .photoLoadingFailed:
                state.photoErrorMessage = "사진을 불러오지 못했습니다."
                return .none

            case .delegate:
                return .none
            }
        }
    }
}

struct InspectionEditorView: View {
    @Bindable var store: StoreOf<InspectionEditorFeature>
    @State private var selectedPhoto: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                Section("점검 대상") {
                    LabeledContent("대상", value: store.target.name)
                    LabeledContent("장비 번호", value: store.target.equipmentNumber)
                }
                
                Section("사진") {
                    if let photoData = store.photoData,
                       let image = UIImage(data: photoData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Text("사진 없음")
                            .foregroundStyle(.secondary)
                    }
                    
                    if store.mode.isEditable {
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label("사진 추가", systemImage: "photo")
                        }
                        .onChange(of: selectedPhoto) { _, newItem in
                            guard let newItem else {
                                return
                            }
                            
                            Task { @MainActor in
                                do {
                                    guard let data = try await newItem.loadTransferable(type: Data.self) else {
                                        store.send(.photoLoadingFailed)
                                        return
                                    }
                                    
                                    store.send(.photoDataLoaded(data))
                                } catch {
                                    store.send(.photoLoadingFailed)
                                }
                            }
                        }
                    }
                    
                    if let photoErrorMessage = store.photoErrorMessage {
                        Text(photoErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                
                Section("상태") {
                    if store.mode.isEditable {
                        Picker("상태", selection: $store.status) {
                            Text("선택 안 함")
                                .tag(Optional<InspectionStatus>.none)
                            
                            ForEach(InspectionStatus.allCases, id: \.self) { status in
                                Text(status.title)
                                    .tag(Optional<InspectionStatus>.some(status))
                            }
                        }
                    } else {
                        Text(store.status?.title ?? "상태 미지정")
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section("메모") {
                    if store.mode.isEditable {
                        TextEditor(text: $store.memo)
                            .frame(minHeight: 140)
                    } else if store.memo.isEmpty {
                        Text("메모 없음")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(store.memo)
                    }
                }
            }
            .navigationTitle(store.mode.navigationTitle)
            .toolbar {
                if store.mode.isEditable {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("취소") {
                            store.send(.cancelButtonTapped)
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("저장") {
                            store.send(.saveButtonTapped)
                        }
                    }
                } else {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("닫기") {
                            store.send(.closeButtonTapped)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("수정") {
                            store.send(.editButtonTapped)
                        }
                    }
                }
            }
        }
    }
}

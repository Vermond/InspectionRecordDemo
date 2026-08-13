import ComposableArchitecture
import Foundation

@Reducer
struct TargetFormFeature {
    @ObservableState
    struct State: Equatable {
        enum Mode: Equatable {
            case create
            case edit(id: UUID, createdAt: Date)

            var navigationTitle: String {
                switch self {
                case .create:
                    "점검 대상 추가"
                case .edit:
                    "점검 대상 수정"
                }
            }
        }

        var mode: Mode = .create
        var name = ""
        var equipmentNumber = ""

        init() {}

        init(target: InspectionTarget) {
            self.mode = .edit(id: target.id, createdAt: target.createdAt)
            self.name = target.name
            self.equipmentNumber = target.equipmentNumber
        }

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

                let timestamp = Date()
                let name = state.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let equipmentNumber = state.equipmentNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                let target: InspectionTarget

                switch state.mode {
                case .create:
                    target = InspectionTarget(
                        id: UUID(),
                        name: name,
                        equipmentNumber: equipmentNumber,
                        createdAt: timestamp,
                        updatedAt: timestamp
                    )

                case let .edit(id, createdAt):
                    target = InspectionTarget(
                        id: id,
                        name: name,
                        equipmentNumber: equipmentNumber,
                        createdAt: createdAt,
                        updatedAt: timestamp
                    )
                }

                return .send(.delegate(.saved(target)))

            case .cancelButtonTapped:
                return .send(.delegate(.cancelled))

            case .delegate:
                return .none
            }
        }
    }
}

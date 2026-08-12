import ComposableArchitecture
import Foundation

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

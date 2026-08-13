import ComposableArchitecture
import Foundation

@Reducer
struct TargetDetailFeature {
    @ObservableState
    struct State: Equatable {
        var target: InspectionTarget
        let latestInspectionAt: Date?
        @Presents var destination: Destination.State?

        init(target: InspectionTarget, latestInspectionAt: Date?) {
            self.target = target
            self.latestInspectionAt = latestInspectionAt
            self.destination = nil
        }
    }

    enum Action {
        case editButtonTapped
        case closeButtonTapped
        case destination(PresentationAction<Destination.Action>)
        case delegate(Delegate)

        enum Delegate: Equatable {
            case targetSaveRequested(InspectionTarget)
            case cancelled
        }
    }

    @Reducer
    enum Destination {
        case targetForm(TargetFormFeature)
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .editButtonTapped:
                state.destination = .targetForm(TargetFormFeature.State(target: state.target))
                return .none

            case .closeButtonTapped:
                return .send(.delegate(.cancelled))

            case let .destination(.presented(.targetForm(.delegate(.saved(target))))):
                state.destination = nil
                return .send(.delegate(.targetSaveRequested(target)))

            case .destination(.presented(.targetForm(.delegate(.cancelled)))):
                state.destination = nil
                return .none

            case .destination,
                 .delegate:
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }
}

extension TargetDetailFeature.Destination.State: Equatable {}

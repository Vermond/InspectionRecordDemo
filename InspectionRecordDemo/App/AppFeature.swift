import ComposableArchitecture
import SwiftUI

@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        var inspectionList = InspectionListFeature.State()
    }

    enum Action {
        case inspectionList(InspectionListFeature.Action)
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.inspectionList, action: \.inspectionList) {
            InspectionListFeature()
        }

        Reduce { _, _ in
            .none
        }
    }
}

struct AppView: View {
    let store: StoreOf<AppFeature>
    
    var body: some View {        
        InspectionListView(
            store: store.scope(
                state: \.inspectionList,
                action: \.inspectionList
            )
        )
    }
}

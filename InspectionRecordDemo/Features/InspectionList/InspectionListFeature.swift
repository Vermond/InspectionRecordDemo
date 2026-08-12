import ComposableArchitecture
import Foundation

@Reducer
struct InspectionListFeature {
    @Dependency(\.inspectionRepository) private var inspectionRepository
    @Dependency(\.locationPreferences) private var locationPreferences

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
        var isLoading = false
        var hasLoadedPersistence = false
        var persistenceErrorMessage: String?
        var isLocationPermissionWarningPresented = false
        @Presents var destination: Destination.State?

        var filteredRecords: [InspectionRecord] {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !query.isEmpty else {
                return records
            }

            return records.filter { record in
                record.targetNameSnapshot.localizedCaseInsensitiveContains(query)
                    || record.equipmentNumberSnapshot.localizedCaseInsensitiveContains(query)
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
        case task
        case persistenceLoaded(Result<InspectionRepository.Snapshot, InspectionPersistenceError>)
        case targetPersisted(InspectionTarget)
        case recordPersisted(InspectionRecord)
        case persistenceFailed(InspectionPersistenceError)
        case persistenceErrorDismissed
        case locationPermissionWarningDismissed
        case locationPermissionWarningSuppressionRequested
        case locationPermissionWarningSettingsButtonTapped
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

            case .task:
                guard !state.hasLoadedPersistence, !state.isLoading else {
                    return .none
                }

                state.isLoading = true
                let repository = self.inspectionRepository

                return .run { send in
                    do {
                        let snapshot = try await repository.load()
                        await send(.persistenceLoaded(.success(snapshot)))
                    } catch let error as InspectionPersistenceError {
                        await send(.persistenceLoaded(.failure(error)))
                    } catch {
                        await send(.persistenceLoaded(.failure(.loadFailed)))
                    }
                }

            case let .persistenceLoaded(.success(snapshot)):
                state.targets = snapshot.targets
                state.records = snapshot.records
                state.isLoading = false
                state.hasLoadedPersistence = true
                state.persistenceErrorMessage = nil
                return .none

            case let .persistenceLoaded(.failure(error)):
                state.isLoading = false
                state.hasLoadedPersistence = true
                state.persistenceErrorMessage = error.userMessage
                return .none

            case let .destination(.presented(.targetForm(.delegate(.saved(target))))):
                let repository = self.inspectionRepository

                return .run { send in
                    do {
                        try await repository.saveTarget(target)
                        await send(.targetPersisted(target))
                    } catch let error as InspectionPersistenceError {
                        await send(.persistenceFailed(error))
                    } catch {
                        await send(.persistenceFailed(.saveFailed))
                    }
                }

            case let .targetPersisted(target):
                if !state.targets.contains(where: { $0.id == target.id }) {
                    state.targets.append(target)
                }

                state.destination = nil
                return .none

            case let .destination(.presented(.inspection(.delegate(.saved(record))))):
                let repository = self.inspectionRepository

                return .run { send in
                    do {
                        try await repository.saveRecord(record)
                        await send(.recordPersisted(record))
                    } catch let error as InspectionPersistenceError {
                        await send(.persistenceFailed(error))
                    } catch {
                        await send(.persistenceFailed(.saveFailed))
                    }
                }

            case let .recordPersisted(record):
                if let index = state.records.firstIndex(where: { $0.id == record.id }) {
                    state.records[index] = record
                } else {
                    state.records.insert(record, at: 0)
                }

                state.destination = nil
                let hasCompleteLocation = record.latitude != nil && record.longitude != nil
                state.isLocationPermissionWarningPresented = !hasCompleteLocation
                    && !self.locationPreferences.suppressLocationPermissionWarning()
                return .none

            case let .persistenceFailed(error):
                state.persistenceErrorMessage = error.userMessage
                return .none

            case .persistenceErrorDismissed:
                state.persistenceErrorMessage = nil
                return .none

            case .locationPermissionWarningDismissed,
                 .locationPermissionWarningSettingsButtonTapped:
                state.isLocationPermissionWarningPresented = false
                return .none

            case .locationPermissionWarningSuppressionRequested:
                self.locationPreferences.setSuppressLocationPermissionWarning(true)
                state.isLocationPermissionWarningPresented = false
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

            case .destination(.presented(.targetForm(.delegate(.cancelled)))):
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

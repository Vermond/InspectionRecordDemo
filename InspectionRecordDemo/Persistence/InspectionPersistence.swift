import ComposableArchitecture
import Foundation
import SwiftData

enum InspectionPersistenceError: Error, Equatable, Sendable {
    case storageUnavailable
    case loadFailed
    case saveFailed
    case targetNotFound
    case recordNotFound

    var userMessage: String {
        switch self {
        case .storageUnavailable:
            "점검 저장소를 사용할 수 없습니다."
        case .loadFailed:
            "점검 데이터를 불러오지 못했습니다."
        case .saveFailed:
            "점검 데이터를 저장하지 못했습니다."
        case .targetNotFound:
            "점검 대상 정보를 찾을 수 없습니다."
        case .recordNotFound:
            "점검 기록 정보를 찾을 수 없습니다."
        }
    }
}

struct InspectionRepository: Sendable {
    struct Snapshot: Equatable, Sendable {
        let targets: [InspectionTarget]
        let records: [InspectionRecord]
    }

    var load: @Sendable () async throws -> Snapshot
    var loadPendingRecords: @Sendable () async throws -> [InspectionRecord]
    var saveTarget: @Sendable (InspectionTarget) async throws -> Void
    var saveRecord: @Sendable (InspectionRecord) async throws -> Void
    var updateSyncStatus: @Sendable (UUID, SyncStatus) async throws -> Void
}

@Model
final class InspectionTargetModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var equipmentNumber: String
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \InspectionRecordModel.target)
    var records: [InspectionRecordModel] = []

    init(
        id: UUID,
        name: String,
        equipmentNumber: String,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.equipmentNumber = equipmentNumber
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class InspectionRecordModel {
    @Attribute(.unique) var id: UUID
    var targetID: UUID
    var targetNameSnapshot: String
    var equipmentNumberSnapshot: String
    var createdAt: Date
    var updatedAt: Date
    var latitude: Double?
    var longitude: Double?
    var syncStatusRawValue: String
    @Attribute(.externalStorage) var photoData: Data?
    var statusRawValue: String?
    var memo: String
    var target: InspectionTargetModel?

    init(
        id: UUID,
        targetID: UUID,
        targetNameSnapshot: String,
        equipmentNumberSnapshot: String,
        createdAt: Date,
        updatedAt: Date,
        latitude: Double?,
        longitude: Double?,
        syncStatusRawValue: String,
        photoData: Data?,
        statusRawValue: String?,
        memo: String,
        target: InspectionTargetModel
    ) {
        self.id = id
        self.targetID = targetID
        self.targetNameSnapshot = targetNameSnapshot
        self.equipmentNumberSnapshot = equipmentNumberSnapshot
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.latitude = latitude
        self.longitude = longitude
        self.syncStatusRawValue = syncStatusRawValue
        self.photoData = photoData
        self.statusRawValue = statusRawValue
        self.memo = memo
        self.target = target
    }
}

@ModelActor
actor InspectionDatabase {
    func load() throws -> InspectionRepository.Snapshot {
        do {
            let targetModels = try modelContext.fetch(FetchDescriptor<InspectionTargetModel>())
            let recordModels = try modelContext.fetch(FetchDescriptor<InspectionRecordModel>())

            let targets = targetModels
                .map(\.domainValue)
                .sorted { $0.name < $1.name }
            let records = recordModels
                .map(\.domainValue)
                .sorted { $0.createdAt > $1.createdAt }

            return InspectionRepository.Snapshot(targets: targets, records: records)
        } catch {
            throw InspectionPersistenceError.loadFailed
        }
    }

    func loadPendingRecords() throws -> [InspectionRecord] {
        let pendingRawValue = SyncStatus.pending.rawValue
        let descriptor = FetchDescriptor<InspectionRecordModel>(
            predicate: #Predicate<InspectionRecordModel> { model in
                model.syncStatusRawValue == pendingRawValue
            }
        )

        do {
            return try modelContext
                .fetch(descriptor)
                .map(\.domainValue)
                .sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            throw InspectionPersistenceError.loadFailed
        }
    }

    func saveTarget(_ target: InspectionTarget) throws {
        let targetID = target.id

        do {
            let descriptor = FetchDescriptor<InspectionTargetModel>(
                predicate: #Predicate<InspectionTargetModel> { model in
                    model.id == targetID
                }
            )

            if let existingTarget = try modelContext.fetch(descriptor).first {
                existingTarget.update(from: target)
            } else {
                modelContext.insert(
                    InspectionTargetModel(
                        id: target.id,
                        name: target.name,
                        equipmentNumber: target.equipmentNumber,
                        createdAt: target.createdAt,
                        updatedAt: target.updatedAt
                    )
                )
            }

            try modelContext.save()
        } catch let error as InspectionPersistenceError {
            throw error
        } catch {
            throw InspectionPersistenceError.saveFailed
        }
    }

    func saveRecord(_ record: InspectionRecord) throws {
        let targetID = record.targetID
        let recordID = record.id

        do {
            let targetDescriptor = FetchDescriptor<InspectionTargetModel>(
                predicate: #Predicate<InspectionTargetModel> { model in
                    model.id == targetID
                }
            )
            guard let target = try modelContext.fetch(targetDescriptor).first else {
                throw InspectionPersistenceError.targetNotFound
            }

            let recordDescriptor = FetchDescriptor<InspectionRecordModel>(
                predicate: #Predicate<InspectionRecordModel> { model in
                    model.id == recordID
                }
            )

            if let existingRecord = try modelContext.fetch(recordDescriptor).first {
                existingRecord.update(from: record, target: target)
            } else {
                modelContext.insert(
                    InspectionRecordModel(
                        id: record.id,
                        targetID: record.targetID,
                        targetNameSnapshot: record.targetNameSnapshot,
                        equipmentNumberSnapshot: record.equipmentNumberSnapshot,
                        createdAt: record.createdAt,
                        updatedAt: record.updatedAt,
                        latitude: record.latitude,
                        longitude: record.longitude,
                        syncStatusRawValue: record.syncStatus.rawValue,
                        photoData: record.photoData,
                        statusRawValue: record.status?.rawValue,
                        memo: record.memo,
                        target: target
                    )
                )
            }

            try modelContext.save()
        } catch let error as InspectionPersistenceError {
            throw error
        } catch {
            throw InspectionPersistenceError.saveFailed
        }
    }

    func updateSyncStatus(for recordID: UUID, to syncStatus: SyncStatus) throws {
        do {
            let descriptor = FetchDescriptor<InspectionRecordModel>(
                predicate: #Predicate<InspectionRecordModel> { model in
                    model.id == recordID
                }
            )
            guard let record = try modelContext.fetch(descriptor).first else {
                throw InspectionPersistenceError.recordNotFound
            }

            record.syncStatusRawValue = syncStatus.rawValue
            try modelContext.save()
        } catch let error as InspectionPersistenceError {
            throw error
        } catch {
            throw InspectionPersistenceError.saveFailed
        }
    }
}

private extension InspectionTargetModel {
    var domainValue: InspectionTarget {
        InspectionTarget(
            id: id,
            name: name,
            equipmentNumber: equipmentNumber,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func update(from target: InspectionTarget) {
        name = target.name
        equipmentNumber = target.equipmentNumber
        updatedAt = target.updatedAt
    }
}

private extension InspectionRecordModel {
    var domainValue: InspectionRecord {
        InspectionRecord(
            id: id,
            targetID: targetID,
            targetNameSnapshot: targetNameSnapshot,
            equipmentNumberSnapshot: equipmentNumberSnapshot,
            createdAt: createdAt,
            updatedAt: updatedAt,
            photoData: photoData,
            status: statusRawValue.flatMap(InspectionStatus.init(rawValue:)),
            memo: memo,
            syncStatus: SyncStatus(rawValue: syncStatusRawValue) ?? .pending,
            latitude: latitude,
            longitude: longitude
        )
    }

    func update(from record: InspectionRecord, target: InspectionTargetModel) {
        targetID = record.targetID
        targetNameSnapshot = record.targetNameSnapshot
        equipmentNumberSnapshot = record.equipmentNumberSnapshot
        createdAt = record.createdAt
        updatedAt = record.updatedAt
        latitude = record.latitude
        longitude = record.longitude
        syncStatusRawValue = record.syncStatus.rawValue
        photoData = record.photoData
        statusRawValue = record.status?.rawValue
        memo = record.memo
        self.target = target
    }
}

extension InspectionRepository: DependencyKey {
    static let liveValue: Self = {
        do {
            let container = try ModelContainer(
                for: InspectionTargetModel.self,
                InspectionRecordModel.self
            )
            let database = InspectionDatabase(modelContainer: container)

            return Self(
                load: {
                    try await database.load()
                },
                loadPendingRecords: {
                    try await database.loadPendingRecords()
                },
                saveTarget: { target in
                    try await database.saveTarget(target)
                },
                saveRecord: { record in
                    try await database.saveRecord(record)
                },
                updateSyncStatus: { recordID, syncStatus in
                    try await database.updateSyncStatus(for: recordID, to: syncStatus)
                }
            )
        } catch {
            return Self(
                load: {
                    throw InspectionPersistenceError.storageUnavailable
                },
                loadPendingRecords: {
                    throw InspectionPersistenceError.storageUnavailable
                },
                saveTarget: { _ in
                    throw InspectionPersistenceError.storageUnavailable
                },
                saveRecord: { _ in
                    throw InspectionPersistenceError.storageUnavailable
                },
                updateSyncStatus: { _, _ in
                    throw InspectionPersistenceError.storageUnavailable
                }
            )
        }
    }()

    static let testValue = Self(
        load: {
            Snapshot(targets: [], records: [])
        },
        loadPendingRecords: {
            []
        },
        saveTarget: { _ in },
        saveRecord: { _ in },
        updateSyncStatus: { _, _ in }
    )
}

extension DependencyValues {
    var inspectionRepository: InspectionRepository {
        get { self[InspectionRepository.self] }
        set { self[InspectionRepository.self] = newValue }
    }
}

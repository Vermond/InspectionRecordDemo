import ComposableArchitecture
import Foundation
import SwiftData

enum InspectionPersistenceError: Error, Equatable, Sendable {
    case storageUnavailable
    case loadFailed
    case saveFailed
    case targetNotFound

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
        }
    }
}

struct InspectionRepository: Sendable {
    struct Snapshot: Equatable, Sendable {
        let targets: [InspectionTarget]
        let records: [InspectionRecord]
    }

    var load: @Sendable () async throws -> Snapshot
    var saveTarget: @Sendable (InspectionTarget) async throws -> Void
    var saveRecord: @Sendable (InspectionRecord) async throws -> Void
}

@Model
final class InspectionTargetModel {
    @Attribute(.unique) var id: UUID
    var name: String
    var equipmentNumber: String

    @Relationship(deleteRule: .nullify, inverse: \InspectionRecordModel.target)
    var records: [InspectionRecordModel] = []

    init(id: UUID, name: String, equipmentNumber: String) {
        self.id = id
        self.name = name
        self.equipmentNumber = equipmentNumber
    }
}

@Model
final class InspectionRecordModel {
    @Attribute(.unique) var id: UUID
    var targetID: UUID
    var targetName: String
    var equipmentNumber: String
    var createdAt: Date
    @Attribute(.externalStorage) var photoData: Data?
    var statusRawValue: String?
    var memo: String
    var target: InspectionTargetModel?

    init(
        id: UUID,
        targetID: UUID,
        targetName: String,
        equipmentNumber: String,
        createdAt: Date,
        photoData: Data?,
        statusRawValue: String?,
        memo: String,
        target: InspectionTargetModel
    ) {
        self.id = id
        self.targetID = targetID
        self.targetName = targetName
        self.equipmentNumber = equipmentNumber
        self.createdAt = createdAt
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
                        equipmentNumber: target.equipmentNumber
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
                        targetName: record.targetName,
                        equipmentNumber: record.equipmentNumber,
                        createdAt: record.createdAt,
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
}

private extension InspectionTargetModel {
    var domainValue: InspectionTarget {
        InspectionTarget(
            id: id,
            name: name,
            equipmentNumber: equipmentNumber
        )
    }

    func update(from target: InspectionTarget) {
        name = target.name
        equipmentNumber = target.equipmentNumber
    }
}

private extension InspectionRecordModel {
    var domainValue: InspectionRecord {
        InspectionRecord(
            id: id,
            targetID: targetID,
            targetName: targetName,
            equipmentNumber: equipmentNumber,
            createdAt: createdAt,
            photoData: photoData,
            status: statusRawValue.flatMap(InspectionStatus.init(rawValue:)),
            memo: memo
        )
    }

    func update(from record: InspectionRecord, target: InspectionTargetModel) {
        targetID = record.targetID
        targetName = record.targetName
        equipmentNumber = record.equipmentNumber
        createdAt = record.createdAt
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
                saveTarget: { target in
                    try await database.saveTarget(target)
                },
                saveRecord: { record in
                    try await database.saveRecord(record)
                }
            )
        } catch {
            return Self(
                load: {
                    throw InspectionPersistenceError.storageUnavailable
                },
                saveTarget: { _ in
                    throw InspectionPersistenceError.storageUnavailable
                },
                saveRecord: { _ in
                    throw InspectionPersistenceError.storageUnavailable
                }
            )
        }
    }()

    static let testValue = Self(
        load: {
            Snapshot(targets: [], records: [])
        },
        saveTarget: { _ in },
        saveRecord: { _ in }
    )
}

extension DependencyValues {
    var inspectionRepository: InspectionRepository {
        get { self[InspectionRepository.self] }
        set { self[InspectionRepository.self] = newValue }
    }
}

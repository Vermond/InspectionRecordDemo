import Foundation

enum InspectionStatus: String, CaseIterable, Equatable, Hashable, Sendable {
    case normal
    case caution
    case abnormal

    var title: String {
        switch self {
        case .normal:
            "정상"
        case .caution:
            "주의"
        case .abnormal:
            "이상"
        }
    }
}

enum SyncStatus: String, Equatable, Sendable {
    case pending
    case synced
}

struct InspectionTarget: Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var equipmentNumber: String
}

struct InspectionRecord: Equatable, Identifiable, Sendable {
    let id: UUID
    let targetID: UUID
    let targetNameSnapshot: String
    let equipmentNumberSnapshot: String
    let createdAt: Date
    let updatedAt: Date
    let latitude: Double?
    let longitude: Double?
    var syncStatus: SyncStatus
    var photoData: Data?
    var status: InspectionStatus?
    var memo: String

    init(
        id: UUID,
        targetID: UUID,
        targetNameSnapshot: String,
        equipmentNumberSnapshot: String,
        createdAt: Date,
        updatedAt: Date,
        photoData: Data?,
        status: InspectionStatus?,
        memo: String,
        syncStatus: SyncStatus = .pending,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.id = id
        self.targetID = targetID
        self.targetNameSnapshot = targetNameSnapshot
        self.equipmentNumberSnapshot = equipmentNumberSnapshot
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.latitude = latitude
        self.longitude = longitude
        self.syncStatus = syncStatus
        self.photoData = photoData
        self.status = status
        self.memo = memo
    }
}

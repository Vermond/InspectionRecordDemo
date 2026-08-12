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

struct InspectionTarget: Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var equipmentNumber: String
}

struct InspectionRecord: Equatable, Identifiable, Sendable {
    let id: UUID
    let targetID: UUID
    let targetName: String
    let equipmentNumber: String
    let createdAt: Date
    var photoData: Data?
    var status: InspectionStatus?
    var memo: String
}

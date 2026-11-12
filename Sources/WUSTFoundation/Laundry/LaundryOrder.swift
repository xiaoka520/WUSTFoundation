import Foundation

public struct LaundryOrder: Decodable, Identifiable, Sendable {
    public let id: String
    public let orderType: Int
    public let orderStatus: Int
    public let machineName: String?
    public let shopName: String?
    public let machineFunctionName: String?
    public let parentTypeId: String?

    private enum CodingKeys: String, CodingKey {
        case id, orderType, orderStatus, machineName, shopName, machineFunctionName, parentTypeId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        orderType = try container.decode(Int.self, forKey: .orderType)
        orderStatus = try container.decode(Int.self, forKey: .orderStatus)
        machineName = try container.decodeIfPresent(String.self, forKey: .machineName)
        shopName = try container.decodeIfPresent(String.self, forKey: .shopName)
        machineFunctionName = try container.decodeIfPresent(String.self, forKey: .machineFunctionName)
        if let numericType = try? container.decode(Int.self, forKey: .parentTypeId) {
            parentTypeId = String(numericType)
        } else {
            parentTypeId = try container.decodeIfPresent(String.self, forKey: .parentTypeId)
        }
    }

    public var isRunningWasher: Bool {
        orderType == 1 && orderStatus == 2 && parentTypeId == "c9892cb4-bd78-40f6-83c2-ba73383b090a"
    }
}

public struct LaundryOrderPage: Sendable {
    public let total: Int
    public let items: [LaundryOrder]
    public let nextPage: Int?
}

public struct LaundryOrderSnapshot: Sendable {
    public let order: LaundryOrder
    public let estimatedCompletionTime: Date?
    public let observedAt: Date
    public let remainingSeconds: Int?

    public func remainingSeconds(at date: Date) -> Int? {
        guard let remainingSeconds else { return nil }
        let elapsed = max(0, date.timeIntervalSince(observedAt))
        return max(0, remainingSeconds - Int(min(elapsed.rounded(.down), Double(remainingSeconds))))
    }
}

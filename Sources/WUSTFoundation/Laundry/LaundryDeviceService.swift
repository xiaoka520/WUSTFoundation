import Foundation

public enum LaundryQueryError: Error, Equatable {
    case invalidQuery
    case invalidResponse
    case unexpectedStatusCode(Int)
    case rejected(Int)
}

public struct LaundryShop: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let distance: Int?
    public let machineCount: Int?
    public let freeMachine: Int?
}

public struct LaundryShopPage: Decodable, Sendable {
    public let total: Int
    public let items: [LaundryShop]
}

public struct LaundryWasher: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String
}

public struct LaundryWasherPage: Sendable {
    public let items: [LaundryWasher]
    public let nextPage: Int?
}

public struct LaundryShopInventory: Sendable {
    public let shop: LaundryShop
    public let allDevices: [LaundryWasher]?
    public let availableDevices: [LaundryWasher]
}

public struct LaundryDeviceService: Sendable {
    private let api: LaundryAPI

    public init() {
        api = LaundryAPI(profile: .safari)
    }

    public init(session: URLSession) {
        api = LaundryAPI(profile: .safari, session: session)
    }

    public func fetchNearbyShops(page: Int = 1) async throws -> LaundryShopPage {
        try await fetchNearbyShops(latitude: 30.439405, longitude: 114.268024, page: page)
    }

    public func fetchNearbyShops(latitude: Double, longitude: Double, page: Int = 1) async throws -> LaundryShopPage {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude), page > 0 else {
            throw LaundryQueryError.invalidQuery
        }
        let result: LaundryShopPage? = try await api.post("shop/nearby/list", fields: [
            "latitude": String(latitude), "longitude": String(longitude),
            "type": "7", "page": String(page), "pageSize": "10",
        ])
        guard let result else { throw LaundryQueryError.invalidResponse }
        return result
    }

    public func fetchAvailableWashers(shopID: String, page: Int = 1) async throws -> LaundryWasherPage {
        guard !shopID.isEmpty, page > 0 else { throw LaundryQueryError.invalidQuery }
        let result: WasherPayload? = try await api.post("machineModel/near/machines", fields: [
            "shopId": shopID, "machineTypeId": "c9892cb4-bd78-40f6-83c2-ba73383b090a",
            "goodsPage": String(page), "pageSize": "100",
        ])
        guard let result else { throw LaundryQueryError.invalidResponse }
        let nextPage = !result.items.isEmpty && result.goodsPage > page ? result.goodsPage : nil
        return LaundryWasherPage(items: result.items, nextPage: nextPage)
    }

    public func fetchInventory(for shop: LaundryShop) async throws -> LaundryShopInventory {
        var page: Int? = 1
        var seenIDs = Set<String>()
        var devices: [LaundryWasher] = []
        while let pageNumber = page {
            let result = try await fetchAvailableWashers(shopID: shop.id, page: pageNumber)
            let newDevices = result.items.filter { seenIDs.insert($0.id).inserted }
            devices.append(contentsOf: newDevices)
            page = newDevices.isEmpty ? nil : result.nextPage
        }

        let sorted = devices.sorted(by: Self.washerComesFirst)
        let allDevices = shop.machineCount == sorted.count ? sorted : nil
        return LaundryShopInventory(shop: shop, allDevices: allDevices, availableDevices: sorted)
    }

    private static func washerComesFirst(_ lhs: LaundryWasher, _ rhs: LaundryWasher) -> Bool {
        let left = washerSortKey(lhs.name)
        let right = washerSortKey(rhs.name)
        if left.area != right.area { return left.area < right.area }
        let comparison = left.name.localizedStandardCompare(right.name)
        if comparison == .orderedSame { return lhs.id < rhs.id }
        return comparison == .orderedAscending
    }

    private static func washerSortKey(_ name: String) -> (area: Int, name: String) {
        guard let direction = name.first, direction == "南" || direction == "北" else {
            return (2, name)
        }
        let suffix = name.dropFirst()
        let buildingAndMachine = suffix.hasPrefix("楼") ? suffix.dropFirst() : suffix
        guard buildingAndMachine.first?.isNumber == true else { return (2, name) }
        return (direction == "南" ? 0 : 1, String(buildingAndMachine))
    }

    private struct WasherPayload: Decodable {
        let items: [LaundryWasher]
        let goodsPage: Int
    }
}

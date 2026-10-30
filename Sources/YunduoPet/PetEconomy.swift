import Foundation

enum PetShopItemKind: String, Codable {
    case consumable
    case toy
    case bed
}
struct PetShopItem: Identifiable, Hashable {
    let id: String
    let name: String
    let price: Int
    let kind: PetShopItemKind

    static let catalog: [PetShopItem] = [
        PetShopItem(id: "chicken-can", name: "鸡肉罐头", price: 2, kind: .consumable),
        PetShopItem(id: "tuna-can", name: "金枪鱼罐头", price: 4, kind: .consumable),
        PetShopItem(id: "yarn-ball", name: "毛线球", price: 8, kind: .toy),
        PetShopItem(id: "laser-pointer", name: "激光笔", price: 25, kind: .toy),
        PetShopItem(id: "cardboard-box", name: "快递纸箱", price: 12, kind: .bed),
        PetShopItem(id: "soft-cushion", name: "柔软坐垫", price: 25, kind: .bed)
    ]

    static func item(withID id: String) -> PetShopItem? {
        catalog.first { $0.id == id }
    }
}

struct FishRewardNotice: Identifiable, Equatable {
    let id = UUID()
    let amount: Int
    let reason: String
}

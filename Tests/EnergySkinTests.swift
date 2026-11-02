import AppKit
import SwiftUI

@main
struct EnergySkinTests {
    @MainActor
    static func main() {
        let suite = "SuannaiEnergySkinTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(180, forKey: "fishBalance")
        let model = PetModel(defaults: defaults, startsServices: false)
        let skins = PetShopItem.catalog.filter { $0.kind == .energySkin }
        assert(skins.count == 3)
        assert(Set(skins.map(\.id)).count == 3)
        assert(model.energyBarSkin == nil)
        for (index, skin) in skins.enumerated() {
            model.purchase(skin)
            assert(model.fishBalance == 180 - 60 * (index + 1))
            assert(model.ownsShopItem(skin))
            assert(model.isShopItemEquipped(skin))
            let balance = model.fishBalance
            model.purchase(skin)
            assert(model.fishBalance == balance, "Duplicate purchase must not charge")
        }
        let restored = PetModel(defaults: defaults, startsServices: false)
        assert(restored.energyBarSkin == .paws)
        assert(restored.ownedShopItemIDs.count == 3)
        assert(restored.fishBalance == 0)
        restored.useOwnedItem(skins[0])
        assert(restored.energyBarSkin == .cream)
        restored.useOwnedItem(skins[0])
        assert(restored.energyBarSkin == nil)
        assert(restored.ownsShopItem(skins[0]))
        assert(PetModel(defaults: defaults, startsServices: false).energyBarSkin == nil)
        restored.setEnergyBarVisible(false)
        restored.useOwnedItem(skins[1])
        assert(!restored.showsEnergyBar, "Equipment must preserve visibility preference")
        assert(restored.fishBalance == 0, "Switching must be free")
        defaults.set([], forKey: "ownedShopItemIDs")
        defaults.set(59, forKey: "fishBalance")
        let poor = PetModel(defaults: defaults, startsServices: false)
        assert(poor.energyBarSkin == nil, "Unowned saved skin must be ignored")
        poor.purchase(skins[0])
        assert(poor.fishBalance == 59 && !poor.ownsShopItem(skins[0]))
        assert(poor.shopMessage == "还差 1 条小鱼干")
        poor.useOwnedItem(skins[0])
        assert(poor.energyBarSkin == nil)
        defaults.set([skins[0].id], forKey: "ownedShopItemIDs")
        defaults.set("unknown-skin", forKey: "equippedEnergySkinID")
        assert(PetModel(defaults: defaults, startsServices: false).energyBarSkin == nil)
        print("PASS: skin purchase, insufficient funds, duplicate purchase, equipment, persistence, visibility, invalid saved data")
    }
}

import AppKit
import SwiftUI

struct PetRootView: View {
    @ObservedObject var model: PetModel
    @State private var pressed = false
    @State private var dragStartOrigin: NSPoint?
    @State private var dragStartMouseLocation: NSPoint?
    @State private var showsSizeControls = false
    @State private var showsShop = false

    var body: some View {
        let baseWidth: CGFloat = model.completionNotice == nil ? 165 : 320
        let baseHeight: CGFloat = 165

        HStack(spacing: 0) {
            if let notice = model.completionNotice {
                CompletionBubble(notice: notice) {
                    model.dismissCompletionNotice()
                }
                .frame(width: 155, height: 165)
                .transition(.scale(scale: 0.9, anchor: .trailing).combined(with: .opacity))
            }

            petContent
                .frame(width: 165, height: 165)
        }
        .frame(width: baseWidth, height: baseHeight, alignment: .trailing)
        .scaleEffect(model.petScale, anchor: .bottomTrailing)
        .frame(
            width: baseWidth * model.petScale,
            height: baseHeight * model.petScale,
            alignment: .bottomTrailing
        )
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: model.completionNotice?.id)
        .animation(.easeOut(duration: 0.16), value: model.petScale)
    }

    private var petContent: some View {
        VStack(spacing: 2) {
            Group {
                if model.showsEnergyBar {
                    WeeklyEnergyBar(remaining: model.weeklyRemaining)
                } else {
                    Color.clear
                }
            }
            .frame(width: 112, height: 19)

            ZStack {
                if let bedID = model.equippedBedID,
                   !model.usesIntegratedBedAnimation,
                   model.visualState == .idle || model.visualState == .idleGrooming ||
                    model.visualState == .idleSleeping || model.visualState == .idleExhausted {
                    PetBedDecoration(itemID: bedID)
                        .offset(y: 43)
                }

                Group {
                    if let frame = model.currentFrame {
                        Image(nsImage: frame)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .frame(
                    width: model.usesIntegratedBedAnimation ? 150 : 115,
                    height: 125
                )
                .scaleEffect(pressed ? 0.97 : 1)
                .animation(.spring(response: 0.18, dampingFraction: 0.72), value: pressed)
                .contentShape(Rectangle())
                .onTapGesture {
                    pressed = true
                    model.handleClick()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        pressed = false
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 3, coordinateSpace: .global)
                        .onChanged { value in
                            guard let window = NSApp.windows.first(where: { $0.isVisible }) else { return }
                            let mouseLocation = NSEvent.mouseLocation
                            if dragStartOrigin == nil || dragStartMouseLocation == nil {
                                dragStartOrigin = window.frame.origin
                                // Recover the mouse-down point from the first gesture
                                // translation so the initial 3pt threshold is included.
                                dragStartMouseLocation = NSPoint(
                                    x: mouseLocation.x - value.translation.width,
                                    y: mouseLocation.y + value.translation.height
                                )
                            }
                            guard let origin = dragStartOrigin,
                                  let startMouseLocation = dragStartMouseLocation
                            else { return }
                            let horizontalDelta = mouseLocation.x - startMouseLocation.x
                            let verticalDelta = mouseLocation.y - startMouseLocation.y
                            window.setFrameOrigin(
                                NSPoint(
                                    x: origin.x + horizontalDelta,
                                    y: origin.y + verticalDelta
                                )
                            )
                            model.updateDrag(horizontal: horizontalDelta)
                        }
                        .onEnded { _ in
                            dragStartOrigin = nil
                            dragStartMouseLocation = nil
                            model.endDrag()
                        }
                )

                if let bubble = model.sleepBubblePresentation {
                    SleepZBubble()
                        .scaleEffect(bubble.scale)
                        .opacity(bubble.opacity)
                        .offset(x: -33, y: -8 + bubble.verticalOffset)
                }

                VStack(spacing: 4) {
                    FishBalanceButton(balance: model.fishBalance) {
                        model.clearShopMessage()
                        showsShop.toggle()
                    }

                    if let notice = model.fishRewardNotice {
                        FishRewardBubble(notice: notice)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .offset(x: 50, y: -35)
            }
            .frame(width: 115, height: 125)
            .help(model.bridgeMessage)
        }
        .padding(.top, 6)
        .frame(width: 165, height: 165)
        .background(Color.clear)
        .contextMenu {
            Button("刷新周用量") { model.refreshUsage() }
            Button("酸奶的小店") {
                model.clearShopMessage()
                showsShop = true
            }
            Toggle(
                "显示能量条",
                isOn: Binding(
                    get: { model.showsEnergyBar },
                    set: { model.setEnergyBarVisible($0) }
                )
            )
            Button("宠物大小…") { showsSizeControls = true }
            Divider()
            Button("退出酸奶") { NSApp.terminate(nil) }
        }
        // Anchor the shop to the whole pet area instead of the fish button.
        // The fish button sits over the cat's upper-right corner, so a popover
        // expanding left from that button covered the pet. Using the pet bounds
        // keeps the popover completely beside the pet.
        .popover(isPresented: $showsShop, arrowEdge: .trailing) {
            PetShopPopover(model: model)
        }
        .popover(isPresented: $showsSizeControls, arrowEdge: .trailing) {
            PetSizePopover(model: model)
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.78), value: model.fishRewardNotice?.id)
    }
}

private struct FishBalanceButton: View {
    let balance: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text("🐟")
                    .font(.system(size: 10))
                Text("\(balance)")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color(red: 0.12, green: 0.21, blue: 0.28))
            }
            .padding(.horizontal, 7)
            .frame(height: 21)
            .background(
                Capsule()
                    .fill(Color(red: 1.0, green: 0.98, blue: 0.94).opacity(0.98))
                    .overlay(Capsule().stroke(Color(red: 0.88, green: 0.80, blue: 0.69), lineWidth: 0.7))
                    .shadow(color: .black.opacity(0.16), radius: 2, y: 1)
            )
        }
        .buttonStyle(.plain)
        .help("酸奶的小店·小鱼干 \(balance)")
        .accessibilityLabel("小鱼干 \(balance)条，打开酸奶的小店")
    }
}

private struct FishRewardBubble: View {
    let notice: FishRewardNotice

    var body: some View {
        Text("🐟 +\(notice.amount)")
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(Color(red: 0.08, green: 0.43, blue: 0.65))
            .padding(.horizontal, 7)
            .frame(height: 19)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.97))
                    .overlay(Capsule().stroke(Color.cyan.opacity(0.45), lineWidth: 0.7))
                    .shadow(color: Color.cyan.opacity(0.20), radius: 2, y: 1)
            )
            .help("\(notice.reason)获得 \(notice.amount) 条小鱼干")
    }
}

private struct PetBedDecoration: View {
    let itemID: String

    var body: some View {
        if let image = ShopItemAssets.image(for: itemID) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: itemID == "soft-cushion" ? 108 : 98, height: 68)
                .accessibilityHidden(true)
        }
    }
}

private enum PetShopTab {
    case shop
    case inventory
}

private struct PetShopPopover: View {
    @ObservedObject var model: PetModel
    @State private var selectedTab: PetShopTab = .shop

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    private var ownedItems: [PetShopItem] {
        PetShopItem.catalog.filter { model.ownsShopItem($0) }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("酸奶的小店")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.12, green: 0.15, blue: 0.17))
                Spacer()
                FishWallet(balance: model.fishBalance)
            }

            if let message = model.shopMessage {
                Text(message)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.08, green: 0.49, blue: 0.66))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 3)
                    .transition(.opacity)
            }

            Group {
                if selectedTab == .shop {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(PetShopItem.catalog) { item in
                                ShopItemCard(item: item, isOwned: model.ownsShopItem(item)) {
                                    model.purchase(item)
                                }
                            }
                        }
                        .padding(.vertical, 1)
                    }
                    .scrollIndicators(.never)
                } else if ownedItems.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "shippingbox")
                            .font(.system(size: 30))
                            .foregroundStyle(.secondary)
                        Text("仓库还是空的")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Text("购买玩具或猫窝后会放在这里")
                            .font(.system(size: 10.5, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(ownedItems) { item in
                                InventoryItemCard(
                                    item: item,
                                    isEquipped: item.kind == .bed && model.equippedBedID == item.id
                                ) {
                                    model.useOwnedItem(item)
                                }
                            }
                        }
                    }
                    .scrollIndicators(.never)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 0) {
                shopTabButton("商店", systemImage: "storefront.fill", tab: .shop)
                Divider().frame(height: 24)
                shopTabButton("仓库", systemImage: "shippingbox.fill", tab: .inventory)
            }
            .padding(4)
            .background(Color(red: 0.97, green: 0.96, blue: 0.93))
            .clipShape(Capsule())
        }
        .padding(14)
        .frame(width: 345, height: 485)
        .background(Color(red: 1.0, green: 0.995, blue: 0.98))
        .animation(.easeOut(duration: 0.16), value: model.shopMessage)
    }

    private func shopTabButton(_ title: String, systemImage: String, tab: PetShopTab) -> some View {
        Button {
            selectedTab = tab
            model.clearShopMessage()
        } label: {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(
                    selectedTab == tab
                        ? Color(red: 0.02, green: 0.62, blue: 0.78)
                        : Color.secondary
                )
                .frame(maxWidth: .infinity, minHeight: 31)
                .background(
                    Capsule()
                        .fill(selectedTab == tab ? Color.cyan.opacity(0.13) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct FishWallet: View {
    let balance: Int

    var body: some View {
        HStack(spacing: 6) {
            Text("🐟")
                .font(.system(size: 17))
            Text("\(balance)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Color(red: 0.98, green: 0.96, blue: 0.91))
        .clipShape(Capsule())
    }
}

private struct ShopItemCard: View {
    let item: PetShopItem
    let isOwned: Bool
    let purchase: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            ShopItemArtwork(itemID: item.id)
                .scaleEffect(0.82)
                .frame(height: 44)

            Text(item.name)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)

            Button(action: purchase) {
                HStack(spacing: 5) {
                    if isOwned {
                        Image(systemName: "checkmark")
                        Text("已拥有")
                    } else {
                        Text("🐟")
                        Text("\(item.price)")
                            .monospacedDigit()
                    }
                }
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.03, green: 0.39, blue: 0.57))
                .frame(maxWidth: .infinity, minHeight: 25)
                .background(Color(red: 0.67, green: 0.94, blue: 0.96))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isOwned)
            .opacity(isOwned ? 0.62 : 1)
        }
        .padding(8)
        .background(Color(red: 0.98, green: 0.97, blue: 0.94))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

private struct InventoryItemCard: View {
    let item: PetShopItem
    let isEquipped: Bool
    let use: () -> Void

    var body: some View {
        VStack(spacing: 5) {
            ShopItemArtwork(itemID: item.id)
                .scaleEffect(0.85)
                .frame(height: 48)
            Text(item.name)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
            Button(isEquipped ? "收回" : (item.kind == .toy ? "玩一下" : "使用"), action: use)
                .buttonStyle(.borderedProminent)
                .tint(isEquipped ? Color(red: 0.43, green: 0.48, blue: 0.50) : Color(red: 0.05, green: 0.67, blue: 0.82))
                .controlSize(.small)
        }
        .padding(9)
        .background(Color(red: 0.98, green: 0.97, blue: 0.94))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

private struct ShopItemArtwork: View {
    let itemID: String

    var body: some View {
        if let image = ShopItemAssets.image(for: itemID) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .accessibilityHidden(true)
        } else {
            Image(systemName: "photo")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
        }
    }
}

@MainActor
private enum ShopItemAssets {
    private static let images: [String: NSImage] = {
        Dictionary(uniqueKeysWithValues: PetShopItem.catalog.compactMap { item in
            guard let url = Bundle.main.url(
                forResource: item.id,
                withExtension: "png",
                subdirectory: "ShopItems"
            ), let image = NSImage(contentsOf: url) else {
                return nil
            }
            return (item.id, image)
        })
    }()

    static func image(for itemID: String) -> NSImage? {
        images[itemID]
    }
}

private struct PetSizePopover: View {
    @ObservedObject var model: PetModel

    private var scaleBinding: Binding<Double> {
        Binding(
            get: { Double(model.petScale) },
            set: { model.setPetScale(CGFloat($0)) }
        )
    }

    private var percentText: String {
        "\(Int((model.petScale * 100).rounded()))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("宠物大小")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
                Text(percentText)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color(red: 0.15, green: 0.48, blue: 0.72))
            }

            HStack(spacing: 9) {
                Image(systemName: "cat.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)

                Slider(
                    value: scaleBinding,
                    in: Double(PetModel.minimumPetScale)...Double(PetModel.maximumPetScale),
                    step: 0.05
                )

                Image(systemName: "cat.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                sizeButton("80%", scale: 0.80)
                sizeButton("100%", scale: 1.00)
                sizeButton("120%", scale: 1.20)
                sizeButton("140%", scale: 1.40)
            }

            HStack {
                Text("75%")
                Spacer()
                Button("恢复标准大小") { model.setPetScale(1) }
                    .buttonStyle(.borderless)
                Spacer()
                Text("150%")
            }
            .font(.system(size: 9.5, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 250)
    }

    private func sizeButton(_ title: String, scale: CGFloat) -> some View {
        Button(title) { model.setPetScale(scale) }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(abs(model.petScale - scale) < 0.01 ? Color.accentColor : nil)
    }
}

private struct SleepZBubble: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.92, green: 0.98, blue: 1.0),
                            Color(red: 0.72, green: 0.88, blue: 1.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 0.8))
                .shadow(color: Color.blue.opacity(0.22), radius: 2, y: 1)
                .frame(width: 15, height: 15)

            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(red: 0.72, green: 0.88, blue: 1.0))
                .frame(width: 4, height: 4)
                .rotationEffect(.degrees(45))
                .offset(y: 1)

            Text("Z")
                .font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.08, green: 0.30, blue: 0.62))
                .offset(y: -3)
        }
        .frame(width: 17, height: 19)
        .accessibilityHidden(true)
    }
}

private struct CompletionBubble: View {
    let notice: CompletionNotice
    let dismiss: () -> Void

    var body: some View {
        Button(action: dismiss) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.78, green: 0.91, blue: 0.74))
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(red: 0.16, green: 0.38, blue: 0.18))
                }
                .frame(width: 25, height: 25)

                VStack(alignment: .leading, spacing: 1) {
                    Text("完成啦")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.12, green: 0.27, blue: 0.39))

                    Text(notice.taskName)
                        .font(.system(size: 8.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 0.25, green: 0.42, blue: 0.55))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text("🐟 +\(notice.fishReward)")
                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.04, green: 0.58, blue: 0.76))
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(width: 145, alignment: .leading)
            .background(
                ZStack(alignment: .trailing) {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Color(red: 0.84, green: 0.94, blue: 1.0).opacity(0.98))
                        .overlay(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .stroke(Color(red: 0.42, green: 0.70, blue: 0.88).opacity(0.72), lineWidth: 0.8)
                        )
                        .shadow(color: .black.opacity(0.22), radius: 5, y: 2)

                    BubblePointer()
                        .fill(Color(red: 0.84, green: 0.94, blue: 1.0).opacity(0.98))
                        .frame(width: 9, height: 16)
                        .offset(x: 7)
                }
            )
        }
        .buttonStyle(.plain)
        .help("点击关闭完成提示")
        .accessibilityLabel("任务完成：\(notice.taskName)。点击关闭")
        .offset(x: -2, y: -24)
    }
}

private struct BubblePointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: 0, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct WeeklyEnergyBar: View {
    let remaining: Double?

    private var clamped: Double? {
        remaining.map { min(max($0, 0), 1) }
    }

    private var valueText: String {
        guard let clamped else { return "--" }
        return "\(Int((clamped * 100).rounded()))%"
    }

    var body: some View {
        GeometryReader { proxy in
            let shellHeight: CGFloat = 17
            let shellY = (proxy.size.height - shellHeight) / 2
            let inset: CGFloat = 2
            let innerHeight = shellHeight - inset * 2
            let innerWidth = max(proxy.size.width - inset * 2, 0)
            let badgeSize: CGFloat = 15
            let badgeY = (proxy.size.height - badgeSize) / 2

            ZStack(alignment: .leading) {
                // One continuous outer shell: icon, fill and value no longer
                // depend on two shapes meeting at a separate seam.
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.10), Color(white: 0.23), Color(white: 0.08)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(Capsule().stroke(Color.white.opacity(0.32), lineWidth: 0.7))
                    .shadow(color: .black.opacity(0.45), radius: 1.5, y: 1)
                    .frame(width: proxy.size.width, height: shellHeight)
                    .offset(y: shellY)

                if let clamped {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.08, green: 0.88, blue: 0.82), Color(red: 0.10, green: 0.72, blue: 0.96)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: innerWidth * clamped, height: innerHeight)
                        .shadow(color: Color.cyan.opacity(0.8), radius: 2.5)
                        .offset(x: inset, y: shellY + inset)
                }

                Text(valueText)
                    .font(.system(size: 6.9, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(clamped == nil ? 0.55 : 0.95))
                    .fixedSize()
                    // Optical correction for the visible glyph bounds inside the cyan fill.
                    .position(x: proxy.size.width / 2 + 2, y: proxy.size.height / 2 + 2)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(white: 0.36), Color(white: 0.08)],
                            center: .topLeading,
                            startRadius: 1,
                            endRadius: 12
                        )
                    )
                    .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 0.6))
                    .shadow(color: .black.opacity(0.38), radius: 1, x: 0.5, y: 0.5)
                    .frame(width: badgeSize, height: badgeSize)
                    .offset(x: 1, y: badgeY)

                Image(systemName: "bolt.fill")
                    .font(.system(size: 7.5, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: badgeSize, height: badgeSize)
                    .offset(x: 1, y: badgeY)
            }
            .accessibilityLabel("本周剩余用量")
            .accessibilityValue(valueText)
            .help(clamped == nil ? "正在读取本周剩余用量" : "本周剩余用量 \(valueText)")
        }
    }
}

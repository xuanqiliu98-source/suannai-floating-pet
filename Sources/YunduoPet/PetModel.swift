import AppKit
import Combine
import Foundation

enum PetVisualState: String {
    case idle
    case idleGrooming
    case idleSleeping
    case idleExhausted
    case working
    case workingPhone
    case workingCoke
    case waitingForApproval
    case completed
    case failed
    case entering
    case clickTail
    case clickMeal
    case clickTurn
    case draggingLeft
    case draggingRight
}

struct CompletionNotice: Identifiable, Equatable {
    let id = UUID()
    let taskName: String
    let fishReward: Int
}

struct SleepBubblePresentation {
    let verticalOffset: CGFloat
    let scale: CGFloat
    let opacity: Double
}

@MainActor
final class PetModel: ObservableObject {
    @Published private(set) var frameIndex = 0
    @Published private(set) var weeklyRemaining: Double?
    @Published private(set) var bridgeMessage = "正在连接 Codex…"
    @Published private(set) var completionNotice: CompletionNotice?
    @Published private(set) var petScale: CGFloat = 1
    @Published private(set) var showsEnergyBar = true
    @Published private(set) var fishBalance = 0
    @Published private(set) var ownedShopItemIDs = Set<String>()
    @Published private(set) var equippedBedID: String?
    @Published private(set) var fishRewardNotice: FishRewardNotice?
    @Published private(set) var shopMessage: String?
    @Published var visualState: PetVisualState = .idle

    static let minimumPetScale: CGFloat = 0.75
    static let maximumPetScale: CGFloat = 1.50

    let idleFrames: [NSImage]
    let idleSoftCushionFrames: [NSImage]
    let idleSoftCushionGroomingFrames: [NSImage]
    let idleSoftCushionSleepingFrames: [NSImage]
    let idleSoftCushionExhaustedFrames: [NSImage]
    let idleCardboardBoxFrames: [NSImage]
    let idleCardboardBoxGroomingFrames: [NSImage]
    let idleCardboardBoxSleepingFrames: [NSImage]
    let idleCardboardBoxExhaustedFrames: [NSImage]
    let idleGroomingFrames: [NSImage]
    let idleSleepingFrames: [NSImage]
    let idleExhaustedFrames: [NSImage]
    let clickTailFrames: [NSImage]
    let clickMealFrames: [NSImage]
    let clickTurnFrames: [NSImage]
    let enteringFrames: [NSImage]
    let draggingRightFrames: [NSImage]
    let draggingLeftFrames: [NSImage]
    let workingFrames: [NSImage]
    let workingPhoneFrames: [NSImage]
    let workingCokeFrames: [NSImage]
    let waitingForApprovalFrames: [NSImage]

    private var animationTimer: Timer?
    private var usageRefreshTimer: Timer?
    private var usageRetryTimer: Timer?
    private var activityRefreshTimer: Timer?
    private var activityRefreshInterval: TimeInterval = 30
    private var idleSleepingTickCount = 0
    private var clickIndex = 0
    private var hasReceivedUsageThisLaunch = false
    private var isCodexWorking = false
    private var isWaitingForApproval = false
    private var nextWorkInterruptionDate: Date?
    private var nextWorkInterruption: PetVisualState?
    private var lastWorkInterruption: PetVisualState?
    private var fishRewardDismissGeneration = 0

    private enum EconomyDefaultsKey {
        static let fishBalance = "fishBalance"
        static let ownedShopItemIDs = "ownedShopItemIDs"
        static let equippedBedID = "equippedBedID"
        static let lastTouchRewardAt = "lastTouchFishRewardAt"
        static let touchRewardDay = "touchFishRewardDay"
        static let touchRewardCount = "touchFishRewardCount"
    }
    private lazy var bridge = CodexBridge(
        onWeeklyRemaining: { [weak self] value in
            Task { @MainActor in
                self?.setWeeklyRemaining(value)
            }
        },
        onStatus: { [weak self] message in
            Task { @MainActor in self?.bridgeMessage = message }
        },
        onActivity: { [weak self] active in
            Task { @MainActor in self?.setCodexWorking(active) }
        },
        onApproval: { [weak self] waiting in
            Task { @MainActor in self?.setWaitingForApproval(waiting) }
        },
        onCompletion: { [weak self] taskName in
            Task { @MainActor in self?.showCompletion(taskName: taskName) }
        }
    )

    init() {
        idleFrames = Self.loadFrames(in: "Idle")
        idleSoftCushionFrames = Self.loadFrames(in: "IdleSoftCushion")
        idleSoftCushionGroomingFrames = Self.loadFrames(in: "IdleSoftCushionGrooming")
        idleSoftCushionSleepingFrames = Self.loadFrames(in: "IdleSoftCushionSleeping")
        idleSoftCushionExhaustedFrames = Self.loadFrames(in: "IdleSoftCushionExhausted")
        idleCardboardBoxFrames = Self.loadFrames(in: "IdleCardboardBox")
        idleCardboardBoxGroomingFrames = Self.loadFrames(in: "IdleCardboardBoxGrooming")
        idleCardboardBoxSleepingFrames = Self.loadFrames(in: "IdleCardboardBoxSleeping")
        idleCardboardBoxExhaustedFrames = Self.loadFrames(in: "IdleCardboardBoxExhausted")
        idleGroomingFrames = Self.loadFrames(in: "IdleGrooming")
        idleSleepingFrames = Self.loadFrames(in: "IdleSleeping")
        idleExhaustedFrames = Self.loadFrames(in: "IdleExhausted")
        clickTailFrames = Self.loadFrames(in: "ClickTail")
        clickMealFrames = Self.loadFrames(in: "ClickMeal")
        clickTurnFrames = Self.loadFrames(in: "ClickTurn")
        enteringFrames = Self.loadFrames(in: "Entering")
        draggingRightFrames = Self.loadFrames(in: "DraggingRight")
        draggingLeftFrames = Self.loadFrames(in: "DraggingLeft")
        workingFrames = Self.loadFrames(in: "Working")
        workingPhoneFrames = Self.loadFrames(in: "WorkingPhone")
        workingCokeFrames = Self.loadFrames(in: "WorkingCoke")
        waitingForApprovalFrames = Self.loadFrames(in: "WaitingForApproval")
        if let savedScale = UserDefaults.standard.object(forKey: "petScale") as? NSNumber {
            petScale = Self.clampedPetScale(CGFloat(savedScale.doubleValue))
        }
        if UserDefaults.standard.object(forKey: "showsEnergyBar") != nil {
            showsEnergyBar = UserDefaults.standard.bool(forKey: "showsEnergyBar")
        }
        fishBalance = max(0, UserDefaults.standard.integer(forKey: EconomyDefaultsKey.fishBalance))
        ownedShopItemIDs = Set(
            UserDefaults.standard.stringArray(forKey: EconomyDefaultsKey.ownedShopItemIDs) ?? []
        )
        if let savedBedID = UserDefaults.standard.string(forKey: EconomyDefaultsKey.equippedBedID),
           ownedShopItemIDs.contains(savedBedID) {
            equippedBedID = savedBedID
        }
        visualState = enteringFrames.isEmpty ? .idle : .entering

        let animationTimer = Timer(timeInterval: 0.16, repeats: true) { [weak self] _ in
            let isEventTracking = RunLoop.current.currentMode == .eventTracking
            Task { @MainActor in
                self?.advanceAnimation(isEventTracking: isEventTracking)
            }
        }
        self.animationTimer = animationTimer
        // Mouse dragging switches AppKit into event-tracking run-loop mode.
        // A default-mode scheduled timer pauses there and leaves the drag
        // sprite frozen on frame zero, so animation must run in common modes.
        RunLoop.main.add(animationTimer, forMode: .common)
        bridge.start()
        usageRefreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.bridge.refreshUsage() }
        }
        usageRetryTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if !self.hasReceivedUsageThisLaunch {
                    self.bridge.refreshUsage()
                } else {
                    self.usageRetryTimer?.invalidate()
                    self.usageRetryTimer = nil
                }
            }
        }
        scheduleActivityRefresh(every: 30)
    }

    var currentFrame: NSImage? {
        let frames = framesForCurrentState
        guard !frames.isEmpty else { return idleFrames.first }
        return frames[min(frameIndex, frames.count - 1)]
    }

    var usesIntegratedBedAnimation: Bool {
        !(integratedBedFramesForCurrentState?.isEmpty ?? true)
    }

    private var integratedBedFramesForCurrentState: [NSImage]? {
        switch equippedBedID {
        case "soft-cushion":
            switch visualState {
            case .idle: return idleSoftCushionFrames
            case .idleGrooming: return idleSoftCushionGroomingFrames
            case .idleSleeping: return idleSoftCushionSleepingFrames
            case .idleExhausted: return idleSoftCushionExhaustedFrames
            default: return nil
            }
        case "cardboard-box":
            switch visualState {
            case .idle: return idleCardboardBoxFrames
            case .idleGrooming: return idleCardboardBoxGroomingFrames
            case .idleSleeping: return idleCardboardBoxSleepingFrames
            case .idleExhausted: return idleCardboardBoxExhaustedFrames
            default: return nil
            }
        default:
            return nil
        }
    }

    var sleepBubblePresentation: SleepBubblePresentation? {
        guard visualState == .idleExhausted else { return nil }
        let startFrame = 6
        let endFrame = 54
        guard frameIndex >= startFrame, frameIndex <= endFrame else { return nil }

        let progress = CGFloat(frameIndex - startFrame) / CGFloat(endFrame - startFrame)
        let fadeIn = min(progress / 0.12, 1)
        let fadeOut = min((1 - progress) / 0.22, 1)
        return SleepBubblePresentation(
            verticalOffset: -12 * progress,
            scale: 0.72 + 0.18 * progress,
            opacity: Double(max(0, min(fadeIn, fadeOut)))
        )
    }

    func handleClick() {
        let reactions: [PetVisualState] = [.clickTail, .clickMeal, .clickTurn]
        visualState = reactions[clickIndex % reactions.count]
        clickIndex += 1
        frameIndex = 0
        tryAwardTouchFish()
    }

    func ownsShopItem(_ item: PetShopItem) -> Bool {
        item.kind != .consumable && ownedShopItemIDs.contains(item.id)
    }

    func purchase(_ item: PetShopItem) {
        shopMessage = nil

        if ownsShopItem(item) {
            shopMessage = "已经拥有「\(item.name)」啦"
            return
        }
        guard fishBalance >= item.price else {
            shopMessage = "还差 \(item.price - fishBalance) 条小鱼干"
            return
        }

        fishBalance -= item.price
        if item.kind != .consumable {
            ownedShopItemIDs.insert(item.id)
            UserDefaults.standard.set(
                Array(ownedShopItemIDs).sorted(),
                forKey: EconomyDefaultsKey.ownedShopItemIDs
            )
        }
        persistFishBalance()

        switch item.kind {
        case .consumable:
            shopMessage = "酸奶开心地吃掉了「\(item.name)」"
            playShopReaction(.clickMeal)
        case .toy:
            shopMessage = "「\(item.name)」已放进仓库"
            playShopReaction(item.id == "yarn-ball" ? .clickTail : .clickTurn)
        case .bed:
            equipBed(item)
            shopMessage = "「\(item.name)」已购买并使用"
        }
    }

    func useOwnedItem(_ item: PetShopItem) {
        guard ownsShopItem(item) else { return }
        shopMessage = nil
        switch item.kind {
        case .toy:
            shopMessage = "酸奶正在玩「\(item.name)」"
            playShopReaction(item.id == "yarn-ball" ? .clickTail : .clickTurn)
        case .bed:
            if equippedBedID == item.id {
                unequipBed()
                shopMessage = "已把「\(item.name)」收回仓库"
            } else {
                equipBed(item)
                shopMessage = "已换上「\(item.name)」"
            }
        case .consumable:
            break
        }
    }

    func clearShopMessage() {
        shopMessage = nil
    }

    func refreshUsage() {
        bridge.refreshUsage()
    }

    func setPetScale(_ scale: CGFloat) {
        let clamped = Self.clampedPetScale(scale)
        guard abs(petScale - clamped) > 0.001 else { return }
        petScale = clamped
        UserDefaults.standard.set(Double(clamped), forKey: "petScale")
    }

    func setEnergyBarVisible(_ isVisible: Bool) {
        guard showsEnergyBar != isVisible else { return }
        showsEnergyBar = isVisible
        UserDefaults.standard.set(isVisible, forKey: "showsEnergyBar")
    }

    func dismissCompletionNotice() {
        completionNotice = nil
    }

    func updateDrag(horizontal translation: CGFloat) {
        let nextState: PetVisualState = translation >= 0 ? .draggingRight : .draggingLeft
        if visualState != nextState {
            visualState = nextState
            // Frame zero is another grounded sitting pose and looked like a
            // frozen replacement image. Begin with the paw-lift frame, then
            // let the common-mode timer advance through the airborne loop.
            frameIndex = 1
        }
    }

    func endDrag() {
        returnToBaseState()
    }

    func shutdown() {
        animationTimer?.invalidate()
        usageRefreshTimer?.invalidate()
        usageRetryTimer?.invalidate()
        activityRefreshTimer?.invalidate()
        bridge.stop()
    }

    private static func loadFrames(in subdirectory: String) -> [NSImage] {
        var frames: [NSImage] = []
        for index in 0..<24 {
            guard let url = Bundle.main.url(
                forResource: String(format: "%02d", index),
                withExtension: "png",
                subdirectory: subdirectory
            ) else { break }
            guard let image = NSImage(contentsOf: url) else { break }
            frames.append(image)
        }
        return frames
    }

    private static func clampedPetScale(_ scale: CGFloat) -> CGFloat {
        min(max(scale, minimumPetScale), maximumPetScale)
    }

    private var framesForCurrentState: [NSImage] {
        if let integratedFrames = integratedBedFramesForCurrentState,
           !integratedFrames.isEmpty {
            return integratedFrames
        }

        switch visualState {
        case .idleExhausted:
            guard idleExhaustedFrames.count == 6 else { return idleExhaustedFrames }
            // Slow belly breathing is continuous; ear and tail twitches are
            // separated by long neutral beats so the cat still feels asleep.
            return [
                idleExhaustedFrames[0], idleExhaustedFrames[0], idleExhaustedFrames[0],
                idleExhaustedFrames[0], idleExhaustedFrames[0],
                idleExhaustedFrames[1], idleExhaustedFrames[1], idleExhaustedFrames[1], idleExhaustedFrames[1],
                idleExhaustedFrames[2], idleExhaustedFrames[2], idleExhaustedFrames[2], idleExhaustedFrames[2],
                idleExhaustedFrames[1], idleExhaustedFrames[1], idleExhaustedFrames[1],
                idleExhaustedFrames[0], idleExhaustedFrames[0], idleExhaustedFrames[0],
                idleExhaustedFrames[0], idleExhaustedFrames[0], idleExhaustedFrames[0]
            ] + Array(repeating: idleExhaustedFrames[0], count: 14) + [
                idleExhaustedFrames[3], idleExhaustedFrames[3],
                idleExhaustedFrames[0], idleExhaustedFrames[0], idleExhaustedFrames[0], idleExhaustedFrames[0],
                idleExhaustedFrames[0], idleExhaustedFrames[0], idleExhaustedFrames[0], idleExhaustedFrames[0],
                idleExhaustedFrames[4], idleExhaustedFrames[4],
                idleExhaustedFrames[0], idleExhaustedFrames[0], idleExhaustedFrames[0], idleExhaustedFrames[0],
                idleExhaustedFrames[0], idleExhaustedFrames[0], idleExhaustedFrames[0], idleExhaustedFrames[0],
                idleExhaustedFrames[5], idleExhaustedFrames[5], idleExhaustedFrames[5],
                idleExhaustedFrames[0], idleExhaustedFrames[0], idleExhaustedFrames[0],
                idleExhaustedFrames[0], idleExhaustedFrames[0]
            ]
        case .idleSleeping:
            guard idleSleepingFrames.count == 2 else { return idleSleepingFrames }
            // Timing is handled in advanceAnimation; the playback list itself
            // contains each retained image exactly once.
            return idleSleepingFrames
        case .idleGrooming:
            guard idleGroomingFrames.count == 8 else { return idleGroomingFrames }
            // Every source pose appears exactly once. Repeating identical
            // images here made the motion look stalled even though the timer
            // was running normally.
            return idleGroomingFrames
        case .clickTail:
            guard clickTailFrames.count == 6 else { return clickTailFrames }
            // A second wag and a short settling beat make the reaction readable.
            let cycle = [
                clickTailFrames[0], clickTailFrames[1],
                clickTailFrames[2], clickTailFrames[3], clickTailFrames[4],
                clickTailFrames[3], clickTailFrames[2],
                clickTailFrames[3], clickTailFrames[4],
                clickTailFrames[5], clickTailFrames[5]
            ]
            return cycle
        case .clickMeal:
            guard clickMealFrames.count == 12 else { return clickMealFrames }
            // Preserve the new in-between motion while holding the actual eating
            // and lip-lick moments long enough for the user to register them.
            let cycle = [
                clickMealFrames[0], clickMealFrames[1], clickMealFrames[2],
                clickMealFrames[3], clickMealFrames[4],
                clickMealFrames[5], clickMealFrames[5],
                clickMealFrames[6], clickMealFrames[6],
                clickMealFrames[7], clickMealFrames[8],
                clickMealFrames[9], clickMealFrames[9],
                clickMealFrames[10], clickMealFrames[11]
            ]
            return cycle
        case .clickTurn:
            guard clickTurnFrames.count == 6 else { return clickTurnFrames }
            // Hold both the direct look and the final proud turn.
            let cycle = [
                clickTurnFrames[0], clickTurnFrames[1],
                clickTurnFrames[2], clickTurnFrames[2], clickTurnFrames[2],
                clickTurnFrames[3], clickTurnFrames[4],
                clickTurnFrames[5], clickTurnFrames[5],
                clickTurnFrames[5], clickTurnFrames[5]
            ]
            return cycle
        case .entering:
            return enteringFrames
        case .draggingRight:
            return draggingRightFrames
        case .draggingLeft:
            return draggingLeftFrames
        case .working:
            return workingFrames
        case .workingPhone:
            guard workingPhoneFrames.count == 16 else { return workingPhoneFrames }
            // Let the phone interaction breathe without replaying the full
            // take-out/put-away sequence. The middle taps loop briefly.
            return [
                workingPhoneFrames[0], workingPhoneFrames[1],
                workingPhoneFrames[2], workingPhoneFrames[3],
                workingPhoneFrames[4], workingPhoneFrames[5],
                workingPhoneFrames[6], workingPhoneFrames[7],
                workingPhoneFrames[8], workingPhoneFrames[8],
                workingPhoneFrames[9], workingPhoneFrames[9],
                workingPhoneFrames[10], workingPhoneFrames[10],
                workingPhoneFrames[11], workingPhoneFrames[11],
                workingPhoneFrames[10], workingPhoneFrames[10],
                workingPhoneFrames[9], workingPhoneFrames[9],
                workingPhoneFrames[12], workingPhoneFrames[13],
                workingPhoneFrames[14], workingPhoneFrames[15]
            ]
        case .workingCoke:
            guard workingCokeFrames.count == 8 else { return workingCokeFrames }
            // The lift and return stay brisk, while the actual sip and the
            // satisfied blink linger long enough to read at floating-pet size.
            return [
                workingCokeFrames[0], workingCokeFrames[0],
                workingCokeFrames[1], workingCokeFrames[1],
                workingCokeFrames[2], workingCokeFrames[2],
                workingCokeFrames[3], workingCokeFrames[3],
                workingCokeFrames[4], workingCokeFrames[4],
                workingCokeFrames[4], workingCokeFrames[4],
                workingCokeFrames[5], workingCokeFrames[5],
                workingCokeFrames[5], workingCokeFrames[5],
                workingCokeFrames[6], workingCokeFrames[6],
                workingCokeFrames[7], workingCokeFrames[7]
            ]
        case .waitingForApproval:
            return waitingForApprovalFrames
        default:
            return idleFrames
        }
    }

    private func advanceAnimation(isEventTracking: Bool) {
        // Both a window drag and an open NSMenu use AppKit's event-tracking
        // run-loop mode. Keep animating during an actual pet drag, but pause
        // all published frame updates while a context menu is tracking. A
        // frame update there rebuilds SwiftUI's nested Menu and dismisses its
        // submenu as soon as the mouse button is released.
        if isEventTracking &&
            visualState != .draggingLeft && visualState != .draggingRight {
            return
        }

        let frames = framesForCurrentState
        guard !frames.isEmpty else { return }

        if visualState == .idleSleeping ||
            (usesIntegratedBedAnimation && visualState != .idleGrooming) {
            // The shared timer fires every 0.16s. Advancing every sixth tick
            // gives a stable ~0.96s cadence without duplicating source frames.
            idleSleepingTickCount += 1
            guard idleSleepingTickCount >= 6 else { return }
            idleSleepingTickCount = 0
            frameIndex = (frameIndex + 1) % frames.count
            return
        }
        if usesIntegratedBedAnimation && visualState == .idleGrooming {
            // Grooming needs to read as one continuous gesture rather than a
            // sequence of held poses. Three ticks gives a ~0.48s cadence.
            idleSleepingTickCount += 1
            guard idleSleepingTickCount >= 3 else { return }
            idleSleepingTickCount = 0
            frameIndex = (frameIndex + 1) % frames.count
            return
        }
        idleSleepingTickCount = 0

        if visualState == .working {
            if let nextWorkInterruptionDate,
               Date() >= nextWorkInterruptionDate,
               let nextWorkInterruption {
                visualState = nextWorkInterruption
                frameIndex = 0
            } else {
                frameIndex = (frameIndex + 1) % frames.count
            }
            return
        }

        if visualState == .idle || visualState == .idleGrooming ||
            visualState == .idleSleeping || visualState == .idleExhausted ||
            visualState == .waitingForApproval {
            frameIndex = (frameIndex + 1) % frames.count
            return
        }

        if visualState == .workingPhone || visualState == .workingCoke {
            if frameIndex + 1 < frames.count {
                frameIndex += 1
            } else {
                lastWorkInterruption = visualState
                scheduleNextWorkInterruption(initial: false)
                returnToBaseState()
            }
            return
        }

        if visualState == .draggingLeft || visualState == .draggingRight {
            if frameIndex + 1 < frames.count {
                frameIndex += 1
            } else {
                frameIndex = min(2, frames.count - 1)
            }
            return
        }

        if frameIndex + 1 < frames.count {
            frameIndex += 1
        } else {
            returnToBaseState()
        }
    }

    private func setCodexWorking(_ active: Bool) {
        let didChange = isCodexWorking != active
        isCodexWorking = active
        updateActivityRefreshSchedule()
        if active {
            completionNotice = nil
            if didChange {
                lastWorkInterruption = nil
                scheduleNextWorkInterruption(initial: true)
            }
            if !isWaitingForApproval &&
                (visualState == .idle || visualState == .idleGrooming ||
                    visualState == .idleSleeping || visualState == .idleExhausted ||
                    visualState == .entering) {
                visualState = workingFrames.isEmpty ? .idle : .working
                frameIndex = 0
            }
        } else {
            nextWorkInterruptionDate = nil
            nextWorkInterruption = nil
            lastWorkInterruption = nil
            if visualState == .working || visualState == .workingPhone || visualState == .workingCoke {
                returnToBaseState()
            }
        }
    }

    private func scheduleNextWorkInterruption(initial: Bool) {
        var available: [PetVisualState] = []
        if !workingPhoneFrames.isEmpty { available.append(.workingPhone) }
        if !workingCokeFrames.isEmpty { available.append(.workingCoke) }

        guard !available.isEmpty else {
            nextWorkInterruptionDate = nil
            nextWorkInterruption = nil
            return
        }

        let alternatives = available.filter { $0 != lastWorkInterruption }
        nextWorkInterruption = (alternatives.isEmpty ? available : alternatives).randomElement()
        let delay = initial
            ? Double.random(in: 25...50)
            : Double.random(in: 55...110)
        nextWorkInterruptionDate = Date().addingTimeInterval(delay)
    }

    private func showCompletion(taskName: String) {
        awardFish(1, reason: "完成任务")
        completionNotice = CompletionNotice(taskName: taskName, fishReward: 1)
    }

    private func awardFish(_ amount: Int, reason: String) {
        guard amount > 0 else { return }
        fishBalance += amount
        persistFishBalance()
        fishRewardDismissGeneration += 1
        let generation = fishRewardDismissGeneration
        fishRewardNotice = FishRewardNotice(amount: amount, reason: reason)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
            guard let self, generation == self.fishRewardDismissGeneration else { return }
            self.fishRewardNotice = nil
        }
    }

    private func tryAwardTouchFish() {
        let defaults = UserDefaults.standard
        let now = Date()
        let dayKey = Self.localDayKey(for: now)
        var rewardsToday = defaults.integer(forKey: EconomyDefaultsKey.touchRewardCount)
        if defaults.string(forKey: EconomyDefaultsKey.touchRewardDay) != dayKey {
            rewardsToday = 0
            defaults.set(dayKey, forKey: EconomyDefaultsKey.touchRewardDay)
            defaults.set(0, forKey: EconomyDefaultsKey.touchRewardCount)
        }

        guard rewardsToday < 5 else { return }
        let lastRewardAt = defaults.double(forKey: EconomyDefaultsKey.lastTouchRewardAt)
        guard lastRewardAt == 0 || now.timeIntervalSince1970 - lastRewardAt >= 10 * 60 else { return }
        guard Int.random(in: 1...100) <= 15 else { return }

        let amount = Int.random(in: 1...3)
        defaults.set(now.timeIntervalSince1970, forKey: EconomyDefaultsKey.lastTouchRewardAt)
        defaults.set(rewardsToday + 1, forKey: EconomyDefaultsKey.touchRewardCount)
        awardFish(amount, reason: "摸摸酸奶")
    }

    private func playShopReaction(_ state: PetVisualState) {
        guard !isCodexWorking, !isWaitingForApproval else { return }
        visualState = state
        frameIndex = 0
    }

    private func equipBed(_ item: PetShopItem) {
        guard item.kind == .bed else { return }
        equippedBedID = item.id
        frameIndex = 0
        idleSleepingTickCount = 0
        UserDefaults.standard.set(item.id, forKey: EconomyDefaultsKey.equippedBedID)
    }

    private func unequipBed() {
        equippedBedID = nil
        frameIndex = 0
        idleSleepingTickCount = 0
        UserDefaults.standard.removeObject(forKey: EconomyDefaultsKey.equippedBedID)
    }

    private func persistFishBalance() {
        UserDefaults.standard.set(fishBalance, forKey: EconomyDefaultsKey.fishBalance)
    }

    private static func localDayKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    private func setWeeklyRemaining(_ value: Double) {
        weeklyRemaining = value
        hasReceivedUsageThisLaunch = true
        usageRetryTimer?.invalidate()
        usageRetryTimer = nil
        bridgeMessage = "周剩余用量 \(Int((value * 100).rounded()))%"

        if !isCodexWorking,
           !isWaitingForApproval,
           (visualState == .idle || visualState == .idleGrooming ||
            visualState == .idleSleeping || visualState == .idleExhausted) {
            let nextState = idleStateForUsage
            if visualState != nextState {
                visualState = nextState
                frameIndex = 0
            }
        }
    }

    private var idleStateForUsage: PetVisualState {
        guard let weeklyRemaining else {
            return .idle
        }
        if weeklyRemaining >= 0.40,
           weeklyRemaining < 0.70,
           !idleGroomingFrames.isEmpty {
            return .idleGrooming
        }
        if weeklyRemaining >= 0.20,
           weeklyRemaining < 0.40,
           !idleSleepingFrames.isEmpty {
            return .idleSleeping
        }
        if weeklyRemaining < 0.20,
           !idleExhaustedFrames.isEmpty {
            return .idleExhausted
        }
        return .idle
    }

    private func setWaitingForApproval(_ waiting: Bool) {
        guard isWaitingForApproval != waiting else { return }
        isWaitingForApproval = waiting
        updateActivityRefreshSchedule()

        if waiting, !waitingForApprovalFrames.isEmpty {
            visualState = .waitingForApproval
            frameIndex = 0
        } else if visualState == .waitingForApproval {
            returnToBaseState()
        }
    }

    private func returnToBaseState() {
        if isWaitingForApproval && !waitingForApprovalFrames.isEmpty {
            visualState = .waitingForApproval
        } else {
            visualState = isCodexWorking && !workingFrames.isEmpty ? .working : idleStateForUsage
        }
        frameIndex = 0
    }

    private func updateActivityRefreshSchedule() {
        let interval: TimeInterval
        if isWaitingForApproval {
            interval = 1
        } else if isCodexWorking {
            interval = 2
        } else {
            interval = 30
        }
        scheduleActivityRefresh(every: interval)
    }

    private func scheduleActivityRefresh(every interval: TimeInterval) {
        guard activityRefreshTimer == nil || activityRefreshInterval != interval else { return }
        activityRefreshTimer?.invalidate()
        activityRefreshInterval = interval
        activityRefreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.bridge.refreshActivity() }
        }
    }
}

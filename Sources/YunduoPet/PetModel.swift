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
    @Published var visualState: PetVisualState = .idle

    static let minimumPetScale: CGFloat = 0.75
    static let maximumPetScale: CGFloat = 1.50

    let idleFrames: [NSImage]
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
        if let cached = UserDefaults.standard.object(forKey: "weeklyRemaining") as? NSNumber {
            weeklyRemaining = min(max(cached.doubleValue, 0), 1)
        }
        if let savedScale = UserDefaults.standard.object(forKey: "petScale") as? NSNumber {
            petScale = Self.clampedPetScale(CGFloat(savedScale.doubleValue))
        }
        visualState = enteringFrames.isEmpty ? .idle : .entering

        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.16, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceAnimation()
            }
        }
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

    func dismissCompletionNotice() {
        completionNotice = nil
    }

    func updateDrag(horizontal translation: CGFloat) {
        let nextState: PetVisualState = translation >= 0 ? .draggingRight : .draggingLeft
        if visualState != nextState {
            visualState = nextState
            frameIndex = 0
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

    private func advanceAnimation() {
        let frames = framesForCurrentState
        guard !frames.isEmpty else { return }

        if visualState == .idleSleeping {
            // The shared timer fires every 0.16s. Advancing every sixth tick
            // gives a stable ~0.96s cadence without duplicating image entries.
            idleSleepingTickCount += 1
            guard idleSleepingTickCount >= 6 else { return }
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
        completionNotice = CompletionNotice(taskName: taskName)
    }

    private func setWeeklyRemaining(_ value: Double) {
        weeklyRemaining = value
        hasReceivedUsageThisLaunch = true
        UserDefaults.standard.set(value, forKey: "weeklyRemaining")
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

import AppKit
import Combine
import SwiftUI

final class PetAppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel?
    private var model: PetModel?
    private var layoutCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let model = PetModel()
        let content = PetRootView(model: model)
        let hostingView = NSHostingView(rootView: content)

        let size = NSSize(width: 165 * model.petScale, height: 165 * model.petScale)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false

        if let visibleFrame = NSScreen.main?.visibleFrame {
            let origin = NSPoint(
                x: visibleFrame.maxX - size.width - 8,
                y: visibleFrame.minY + 8
            )
            panel.setFrameOrigin(origin)
        } else {
            panel.center()
        }

        panel.orderFrontRegardless()
        self.model = model
        self.panel = panel
        layoutCancellable = Publishers.CombineLatest(
            model.$completionNotice.map { $0 != nil }.removeDuplicates(),
            model.$petScale.removeDuplicates()
        )
            .sink { [weak self] isVisible, scale in
                self?.resizePanel(completionVisible: isVisible, scale: scale)
            }
    }

    private func resizePanel(completionVisible: Bool, scale: CGFloat) {
        guard let panel else { return }
        let targetWidth: CGFloat = (completionVisible ? 320 : 165) * scale
        let targetHeight: CGFloat = 165 * scale
        guard abs(panel.frame.width - targetWidth) > 0.5 ||
              abs(panel.frame.height - targetHeight) > 0.5 else { return }

        var frame = panel.frame
        let anchoredRightEdge = frame.maxX
        let anchoredBottomEdge = frame.minY
        frame.size.width = targetWidth
        frame.size.height = targetHeight
        frame.origin.x = anchoredRightEdge - targetWidth
        frame.origin.y = anchoredBottomEdge

        if let visibleFrame = (panel.screen ?? NSScreen.main)?.visibleFrame {
            frame.origin.x = min(
                max(frame.origin.x, visibleFrame.minX),
                max(visibleFrame.minX, visibleFrame.maxX - targetWidth)
            )
            frame.origin.y = min(
                max(frame.origin.y, visibleFrame.minY),
                max(visibleFrame.minY, visibleFrame.maxY - targetHeight)
            )
        }
        panel.setFrame(frame, display: true, animate: false)
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.shutdown()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        guard let panel else { return true }

        let isOnScreen = NSScreen.screens.contains { screen in
            screen.visibleFrame.intersects(panel.frame)
        }
        if !isOnScreen, let visibleFrame = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(
                NSPoint(
                    x: visibleFrame.maxX - panel.frame.width - 8,
                    y: visibleFrame.minY + 8
                )
            )
        }

        panel.orderFrontRegardless()
        return true
    }
}

@main
enum YunduoPetMain {
    private static let delegate = PetAppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }
}

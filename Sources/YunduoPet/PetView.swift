import AppKit
import SwiftUI

struct PetRootView: View {
    @ObservedObject var model: PetModel
    @State private var pressed = false
    @State private var dragStartOrigin: NSPoint?
    @State private var dragStartMouseLocation: NSPoint?
    @State private var showsSizeControls = false

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
            WeeklyEnergyBar(remaining: model.weeklyRemaining)
                .frame(width: 112, height: 19)

            ZStack {
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

                if let bubble = model.sleepBubblePresentation {
                    SleepZBubble()
                        .scaleEffect(bubble.scale)
                        .opacity(bubble.opacity)
                        .offset(x: -33, y: -37 + bubble.verticalOffset)
                }
            }
            .frame(width: 115, height: 125)
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
            .help(model.bridgeMessage)
        }
        .padding(.top, 6)
        .frame(width: 165, height: 165)
        .background(Color.clear)
        .contextMenu {
            Button("刷新周用量") { model.refreshUsage() }
            Menu("宠物大小") {
                petSizeButton("小巧", percent: 80, scale: 0.80)
                petSizeButton("标准", percent: 100, scale: 1.00)
                petSizeButton("较大", percent: 120, scale: 1.20)
                petSizeButton("大号", percent: 140, scale: 1.40)
                Divider()
                Button("自定义…") { showsSizeControls = true }
            }
            Divider()
            Button("退出酸奶") { NSApp.terminate(nil) }
        }
        .popover(isPresented: $showsSizeControls, arrowEdge: .trailing) {
            PetSizePopover(model: model)
        }
    }

    private func petSizeButton(_ title: String, percent: Int, scale: CGFloat) -> some View {
        Button {
            model.setPetScale(scale)
        } label: {
            HStack {
                Text("\(title) \(percent)%")
                if abs(model.petScale - scale) < 0.01 {
                    Image(systemName: "checkmark")
                }
            }
        }
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
                .frame(width: 19, height: 19)

            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(red: 0.72, green: 0.88, blue: 1.0))
                .frame(width: 5, height: 5)
                .rotationEffect(.degrees(45))
                .offset(y: 1)

            Text("Z")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.08, green: 0.30, blue: 0.62))
                .offset(y: -4)
        }
        .frame(width: 21, height: 23)
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

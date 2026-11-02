import SwiftUI

struct WeeklyEnergyBar: View {
    let remaining: Double?
    var skin: EnergyBarSkin? = nil

    private var fraction: Double { min(max(remaining ?? 0, 0), 1) }
    private var valueText: String {
        remaining == nil ? "--" : "\(Int((fraction * 100).rounded()))%"
    }

    var body: some View {
        Group {
            if let skin {
                themedBar(skin)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("本周剩余用量")
                    .accessibilityValue(valueText)
                    .help(remaining == nil ? "正在读取本周剩余用量" : "本周剩余用量 \(valueText)")
            } else {
                ClassicWeeklyEnergyBar(remaining: remaining)
            }
        }
    }

    private func themedBar(_ skin: EnergyBarSkin) -> some View {
        let palette = EnergySkinPalette(skin)
        return GeometryReader { proxy in
            let height = min(proxy.size.height, 21)
            HStack(spacing: 3) {
                if skin == .paws {
                    HStack(spacing: 2) {
                        ForEach(0..<5) { index in
                            GeometryReader { paw in
                                let fill = min(max(fraction * 5 - Double(index), 0), 1)
                                Image(systemName: "pawprint.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundStyle(palette.track)
                                    .overlay {
                                        Image(systemName: "pawprint.fill")
                                            .resizable()
                                            .scaledToFit()
                                            .foregroundStyle(palette.accent)
                                            .mask(alignment: .leading) {
                                                Rectangle().frame(width: paw.size.width * fill)
                                            }
                                    }
                            }
                        }
                    }
                    .frame(height: height * 0.52)
                    Text(valueText)
                        .font(.system(size: 7.5, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(palette.ink)
                        .fixedSize()
                } else {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: height - 4, height: height - 4)
                        .background(Circle().fill(palette.accent.gradient))
                    GeometryReader { track in
                        Capsule()
                            .fill(palette.track)
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(LinearGradient(
                                        colors: [palette.accent, palette.accent.opacity(0.48)],
                                        startPoint: .leading, endPoint: .trailing
                                    ))
                                    .frame(width: track.size.width * fraction)
                            }
                            .overlay {
                                Text(valueText)
                                    .font(.system(size: 7.5, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(palette.ink)
                            }
                    }
                    .frame(height: height - 6)
                }
            }
            .padding(.horizontal, skin == .paws ? 6 : 3)
            .frame(height: height)
            .background(Capsule().fill(palette.shell))
            .overlay(Capsule().stroke(palette.border, lineWidth: 0.7))
            .shadow(color: palette.accent.opacity(0.17), radius: 2, y: 1)
            .frame(height: proxy.size.height)
        }
    }
}

struct EnergySkinPalette {
    let shell: Color
    let track: Color
    let accent: Color
    let border: Color
    let ink: Color

    init(_ skin: EnergyBarSkin) {
        switch skin {
        case .cream:
            shell = Color(red: 1, green: 0.97, blue: 0.92)
            track = Color(red: 0.94, green: 0.89, blue: 0.83)
            accent = Color(red: 1, green: 0.65, blue: 0.43)
            border = Color(red: 0.92, green: 0.82, blue: 0.71)
            ink = Color(red: 0.43, green: 0.24, blue: 0.16)
        case .mint:
            shell = Color(red: 0.96, green: 1, blue: 0.99)
            track = Color(red: 0.86, green: 0.96, blue: 0.93)
            accent = Color(red: 0.16, green: 0.81, blue: 0.68)
            border = Color(red: 0.77, green: 0.94, blue: 0.89)
            ink = Color(red: 0.04, green: 0.35, blue: 0.32)
        case .paws:
            shell = Color(red: 0.96, green: 0.94, blue: 1)
            track = Color(red: 0.84, green: 0.80, blue: 0.92)
            accent = Color(red: 0.64, green: 0.46, blue: 0.88)
            border = Color(red: 0.83, green: 0.75, blue: 0.97)
            ink = Color(red: 0.33, green: 0.20, blue: 0.55)
        }
    }
}

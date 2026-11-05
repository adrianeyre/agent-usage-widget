import AgentUsageCore
import SwiftUI

/// A horizontal bar with its fill and Pace marker (F2, P1, §6.1).
/// Bar about 10 pt high with rounded ends; marker 2 pt wide, 3 pt over and under the bar,
/// in the primary label colour so it shows over both the fill and the empty track. A
/// hairline in the background colour either side of the marker keeps it legible where
/// it crosses the end of the fill.
public struct UsageBarView: View {
    public static let barHeight: CGFloat = 10
    public static let markerWidth: CGFloat = 2
    public static let markerOverhang: CGFloat = 3

    let limit: LimitDisplay
    var barHeight: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(limit: LimitDisplay, barHeight: CGFloat = UsageBarView.barHeight) {
        self.limit = limit
        self.barHeight = barHeight
    }

    public var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.10))
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
                    .frame(height: barHeight)
                Capsule()
                    .fill(limit.band.color.gradient)
                    .frame(width: fillWidth(in: width), height: barHeight)
                if let marker = limit.markerFraction {
                    let x = min(max(0, width * marker - Self.markerWidth / 2), width - Self.markerWidth)
                    RoundedRectangle(cornerRadius: Self.markerWidth / 2)
                        .fill(Color.primary)
                        .frame(width: Self.markerWidth, height: barHeight + 2 * Self.markerOverhang)
                        .padding(.horizontal, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.background)
                                .opacity(0.9)
                        )
                        .offset(x: x - 1)
                }
            }
            .frame(height: proxy.size.height)
            .animation(reduceMotion ? nil : .smooth(duration: 0.45), value: limit.fillFraction)
            .animation(reduceMotion ? nil : .smooth(duration: 0.45), value: limit.markerFraction)
        }
        .frame(height: barHeight + 2 * Self.markerOverhang)
        .accessibilityElement()
        .accessibilityLabel(Text(limit.name))
        .accessibilityValue(Text([limit.percentText, limit.paceLabel, limit.detailText].compactMap { $0 }.joined(separator: ", ")))
    }

    /// A non-zero fill is never narrower than the bar is tall, so its rounded end shows.
    private func fillWidth(in width: CGFloat) -> CGFloat {
        guard limit.fillFraction > 0 else { return 0 }
        return min(width, max(barHeight, width * limit.fillFraction))
    }
}

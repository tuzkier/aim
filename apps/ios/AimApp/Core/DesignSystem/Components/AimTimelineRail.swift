import SwiftUI

struct AimTimelineRail: View {
    let position: TimelineWeek.Position
    var showsDot: Bool = false

    private var isFuture: Bool { position == .future }
    private var isAnchor: Bool { position == .current && showsDot }

    var body: some View {
        ZStack(alignment: .top) {
            Color.aimCanvas

            HStack(spacing: 0) {
                line
                    .frame(width: AimMetrics.railWidth)
                    .padding(.leading, AimMetrics.railInset)
                Spacer(minLength: 0)
            }

            if showsDot {
                HStack(spacing: 0) {
                    dot.padding(.leading, dotLeadingInset)
                    Spacer(minLength: 0)
                }
                .padding(.top, AimMetrics.space4)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var line: some View {
        if isFuture {
            DashedLine().stroke(Color.aimRail, style: StrokeStyle(lineWidth: AimMetrics.railWidth, dash: [3, 3]))
        } else {
            Color.aimRail
        }
    }

    @ViewBuilder
    private var dot: some View {
        if isAnchor {
            Circle()
                .fill(Color.aimAccent)
                .frame(width: AimMetrics.railAnchorSize, height: AimMetrics.railAnchorSize)
                .overlay {
                    Circle().stroke(Color.aimAccentSoft, lineWidth: AimMetrics.railAnchorHalo)
                }
        } else {
            Circle()
                .fill(Color.aimCanvas)
                .frame(width: AimMetrics.railDotSize, height: AimMetrics.railDotSize)
                .overlay {
                    Circle().stroke(Color.aimRail, lineWidth: AimMetrics.railDotStroke)
                }
        }
    }

    private var dotLeadingInset: CGFloat {
        let size = isAnchor ? AimMetrics.railAnchorSize : AimMetrics.railDotSize
        return AimMetrics.railInset - size / 2
    }
}

private struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

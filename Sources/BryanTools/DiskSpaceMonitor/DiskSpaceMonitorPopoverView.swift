import BryanToolsShared
import SwiftUI

struct DiskSpaceMonitorPopoverView: View {
    @ObservedObject var environment: DiskSpaceMonitorModule
    @State private var hoveredSample: DiskSpaceSample?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Free Disk Space")
                        .font(.system(size: 16, weight: .semibold))
                    Text(lastMeasuredText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(environment.trayTitle)
                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                    .foregroundStyle(environment.isBelowWarningThreshold ? Color.red : Color.primary)
            }

            if environment.samples.isEmpty {
                Spacer()
                Text("No samples yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                DiskSpaceTrendGraph(samples: environment.samples, hoveredSample: $hoveredSample)
                    .frame(height: 112)

                HStack {
                    Text(hoverText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer()
                }
            }
        }
        .padding(14)
        .frame(width: 300, height: 210, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var lastMeasuredText: String {
        guard let latest = environment.latestSample else {
            return "Last measured: Not measured yet"
        }
        return "Last measured: \(Self.dateFormatter.string(from: latest.sampledAt))"
    }

    private var hoverText: String {
        guard let sample = hoveredSample ?? environment.latestSample else {
            return ""
        }
        return "\(Self.dateFormatter.string(from: sample.sampledAt)) - \(DiskSpaceMonitorDisplay.trayTitle(availableBytes: sample.availableBytes)) free"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct DiskSpaceTrendGraph: View {
    let samples: [DiskSpaceSample]
    @Binding var hoveredSample: DiskSpaceSample?

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                graphPath(size: size)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineJoin: .round))

                if let hoveredSample {
                    let point = point(for: hoveredSample, size: size)
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 7, height: 7)
                        .position(point)

                    Text("\(DiskSpaceMonitorDisplay.trayTitle(availableBytes: hoveredSample.availableBytes))\n\(Self.calloutFormatter.string(from: hoveredSample.sampledAt))")
                        .font(.caption2)
                        .foregroundStyle(.primary)
                        .padding(5)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .position(calloutPosition(for: point, size: size))
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.08))
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoveredSample = nearestSample(to: location, size: size)
                case .ended:
                    hoveredSample = nil
                }
            }
        }
    }

    private func graphPath(size: CGSize) -> Path {
        var path = Path()
        guard let first = samples.first else {
            return path
        }

        path.move(to: point(for: first, size: size))
        for sample in samples.dropFirst() {
            path.addLine(to: point(for: sample, size: size))
        }
        return path
    }

    private func point(for sample: DiskSpaceSample, size: CGSize) -> CGPoint {
        let domain = dateDomain
        let range = valueRange
        let x: CGFloat
        if domain.max <= domain.min {
            x = size.width / 2
        } else {
            x = CGFloat((sample.sampledAt.timeIntervalSince1970 - domain.min) / (domain.max - domain.min)) * size.width
        }

        let y: CGFloat
        if range.max <= range.min {
            y = size.height / 2
        } else {
            let normalized = CGFloat((Double(sample.availableBytes) - range.min) / (range.max - range.min))
            y = (1 - normalized) * size.height
        }
        return CGPoint(x: min(max(x, 0), size.width), y: min(max(y, 0), size.height))
    }

    private func nearestSample(to location: CGPoint, size: CGSize) -> DiskSpaceSample? {
        samples.min { lhs, rhs in
            abs(point(for: lhs, size: size).x - location.x) < abs(point(for: rhs, size: size).x - location.x)
        }
    }

    private var dateDomain: (min: Double, max: Double) {
        let values = samples.map { $0.sampledAt.timeIntervalSince1970 }
        return (values.min() ?? 0, values.max() ?? 0)
    }

    private var valueRange: (min: Double, max: Double) {
        let values = samples.map { Double($0.availableBytes) }
        guard let min = values.min(), let maxValue = values.max() else {
            return (0, 0)
        }
        if min == maxValue {
            let padding = Swift.max(maxValue * 0.05, Double(DiskSpaceMonitorDisplay.bytesPerDecimalGB))
            return (min - padding, maxValue + padding)
        }
        let padding = (maxValue - min) * 0.1
        return (min - padding, maxValue + padding)
    }

    private func calloutPosition(for point: CGPoint, size: CGSize) -> CGPoint {
        let x = min(max(point.x, 58), size.width - 58)
        let y = point.y < 34 ? point.y + 32 : point.y - 30
        return CGPoint(x: x, y: min(max(y, 22), size.height - 22))
    }

    private static let calloutFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

import SwiftUI
import Charts

struct ChartWindowView: View {
    let windowId: String
    let payload: ChartPayload

    @Environment(WindowManager.self) private var windowManager
    @State private var animateChart = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(payload.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)

                Spacer()

                Button(action: { windowManager.closeWindow(id: windowId) }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }

            chartView
                .frame(minHeight: 300)
                .animation(.easeInOut(duration: 0.8), value: animateChart)
        }
        .padding(24)
        .glassBackgroundEffect()
        .onAppear { animateChart = true }
    }

    @ViewBuilder
    private var chartView: some View {
        switch payload.chartType {
        case .bar:
            barChart
        case .line:
            lineChart
        case .area:
            areaChart
        case .pie:
            pieChart
        case .donut:
            donutChart
        case .scatter:
            scatterChart
        }
    }

    private var barChart: some View {
        Chart(payload.data) { point in
            BarMark(
                x: .value(payload.xLabel ?? "Category", point.label),
                y: .value(payload.yLabel ?? "Value", animateChart ? point.value : 0)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [.cyan, .blue],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .cornerRadius(6)
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(.white.opacity(0.15))
                AxisValueLabel()
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private var lineChart: some View {
        Chart(payload.data) { point in
            LineMark(
                x: .value(payload.xLabel ?? "Category", point.label),
                y: .value(payload.yLabel ?? "Value", animateChart ? point.value : 0)
            )
            .foregroundStyle(.cyan)
            .lineStyle(StrokeStyle(lineWidth: 3))

            PointMark(
                x: .value(payload.xLabel ?? "Category", point.label),
                y: .value(payload.yLabel ?? "Value", animateChart ? point.value : 0)
            )
            .foregroundStyle(.white)
            .symbolSize(40)
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(.white.opacity(0.15))
                AxisValueLabel()
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private var areaChart: some View {
        Chart(payload.data) { point in
            AreaMark(
                x: .value(payload.xLabel ?? "Category", point.label),
                y: .value(payload.yLabel ?? "Value", animateChart ? point.value : 0)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [.cyan.opacity(0.6), .cyan.opacity(0.1)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            LineMark(
                x: .value(payload.xLabel ?? "Category", point.label),
                y: .value(payload.yLabel ?? "Value", animateChart ? point.value : 0)
            )
            .foregroundStyle(.cyan)
            .lineStyle(StrokeStyle(lineWidth: 2))
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(.white.opacity(0.15))
                AxisValueLabel()
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private var pieChart: some View {
        Chart(payload.data) { point in
            SectorMark(
                angle: .value("Value", animateChart ? point.value : 0),
                innerRadius: .ratio(0),
                angularInset: 2
            )
            .foregroundStyle(by: .value("Category", point.label))
            .cornerRadius(4)
        }
        .chartLegend(position: .bottom) {
            HStack(spacing: 16) {
                ForEach(payload.data) { point in
                    Label(point.label, systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
    }

    private var donutChart: some View {
        Chart(payload.data) { point in
            SectorMark(
                angle: .value("Value", animateChart ? point.value : 0),
                innerRadius: .ratio(0.55),
                angularInset: 2
            )
            .foregroundStyle(by: .value("Category", point.label))
            .cornerRadius(4)
        }
        .chartLegend(position: .bottom) {
            HStack(spacing: 16) {
                ForEach(payload.data) { point in
                    Label(point.label, systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
    }

    private var scatterChart: some View {
        Chart(payload.data.enumerated().map { (index: $0.offset, point: $0.element) }, id: \.point.id) { item in
            PointMark(
                x: .value(payload.xLabel ?? "Index", item.index),
                y: .value(payload.yLabel ?? "Value", animateChart ? item.point.value : 0)
            )
            .foregroundStyle(.cyan)
            .symbolSize(80)
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(.white.opacity(0.15))
                AxisValueLabel()
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}

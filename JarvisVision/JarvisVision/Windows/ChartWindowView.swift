import SwiftUI
import Charts

struct ChartWindowView: View {
    let windowId: String
    let payload: ChartPayload

    @Environment(WindowManager.self) private var windowManager
    @State private var animateChart = false
    @State private var appeared = false

    // Jarvis chart color palette — Iron Man holographic tones
    private let chartColors: [Color] = [
        JarvisColors.primary,
        JarvisColors.accent,
        Color(red: 0.0, green: 1.0, blue: 0.7),   // seafoam
        JarvisColors.warm,
        Color(red: 0.7, green: 0.5, blue: 1.0),    // violet
        Color(red: 1.0, green: 0.85, blue: 0.3),    // gold
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            JarvisWindowHeader(
                title: payload.title,
                icon: chartIcon,
                onClose: { windowManager.closeWindow(id: windowId) }
            )

            Divider().background(JarvisColors.primary.opacity(0.1))

            // Chart body
            chartView
                .padding(20)
                .animation(.easeInOut(duration: 1.0), value: animateChart)

            // Footer
            chartFooter
        }
        .jarvisPanel()
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.92)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: appeared)
        .onAppear {
            appeared = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                animateChart = true
            }
        }
    }

    private var chartIcon: String {
        switch payload.chartType {
        case .bar: return "chart.bar.fill"
        case .line: return "chart.xyaxis.line"
        case .area: return "chart.line.uptrend.xyaxis"
        case .pie, .donut: return "chart.pie.fill"
        case .scatter: return "circle.dotted"
        }
    }

    private var chartFooter: some View {
        HStack {
            Text("\(payload.data.count) DATA POINTS")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(JarvisColors.textDim)

            Spacer()

            if payload.refreshUrl != nil, let interval = payload.intervalSeconds {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 8))
                    Text("LIVE \(Int(interval))s")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(JarvisColors.success.opacity(0.6))
            }

            Text(timestampString)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(JarvisColors.textDim)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private var timestampString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }

    // MARK: - Chart Routing

    @ViewBuilder
    private var chartView: some View {
        switch payload.chartType {
        case .bar: barChart
        case .line: lineChart
        case .area: areaChart
        case .pie: pieChart
        case .donut: donutChart
        case .scatter: scatterChart
        }
    }

    // MARK: - Bar Chart

    private var barChart: some View {
        Chart(payload.data) { point in
            BarMark(
                x: .value(payload.xLabel ?? "Category", point.label),
                y: .value(payload.yLabel ?? "Value", animateChart ? point.value : 0)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [JarvisColors.primary, JarvisColors.accent.opacity(0.6)],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .cornerRadius(4)
            .annotation(position: .top, spacing: 4) {
                if animateChart {
                    Text(formatValue(point.value))
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(JarvisColors.textSecondary)
                }
            }
        }
        .chartStyle()
        .frame(minHeight: 280)
    }

    // MARK: - Line Chart

    private var lineChart: some View {
        Chart(payload.data) { point in
            LineMark(
                x: .value(payload.xLabel ?? "Category", point.label),
                y: .value(payload.yLabel ?? "Value", animateChart ? point.value : 0)
            )
            .foregroundStyle(JarvisColors.primary)
            .lineStyle(StrokeStyle(lineWidth: 2.5))
            .interpolationMethod(.catmullRom)

            PointMark(
                x: .value(payload.xLabel ?? "Category", point.label),
                y: .value(payload.yLabel ?? "Value", animateChart ? point.value : 0)
            )
            .foregroundStyle(.white)
            .symbolSize(30)
        }
        .chartStyle()
        .frame(minHeight: 280)
    }

    // MARK: - Area Chart

    private var areaChart: some View {
        Chart(payload.data) { point in
            AreaMark(
                x: .value(payload.xLabel ?? "Category", point.label),
                y: .value(payload.yLabel ?? "Value", animateChart ? point.value : 0)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        JarvisColors.primary.opacity(0.5),
                        JarvisColors.primary.opacity(0.05),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value(payload.xLabel ?? "Category", point.label),
                y: .value(payload.yLabel ?? "Value", animateChart ? point.value : 0)
            )
            .foregroundStyle(JarvisColors.primary)
            .lineStyle(StrokeStyle(lineWidth: 2))
            .interpolationMethod(.catmullRom)
        }
        .chartStyle()
        .frame(minHeight: 280)
    }

    // MARK: - Pie Chart

    private var pieChart: some View {
        HStack(spacing: 20) {
            Chart(payload.data) { point in
                SectorMark(
                    angle: .value("Value", animateChart ? point.value : 0.001),
                    innerRadius: .ratio(0),
                    angularInset: 2
                )
                .foregroundStyle(by: .value("Category", point.label))
                .cornerRadius(4)
            }
            .chartForegroundStyleScale(range: chartColors.prefix(payload.data.count).map { $0 })
            .chartLegend(.hidden)
            .frame(width: 200, height: 200)

            chartLegend
        }
        .frame(minHeight: 220)
    }

    // MARK: - Donut Chart

    private var donutChart: some View {
        HStack(spacing: 20) {
            ZStack {
                Chart(payload.data) { point in
                    SectorMark(
                        angle: .value("Value", animateChart ? point.value : 0.001),
                        innerRadius: .ratio(0.55),
                        angularInset: 2
                    )
                    .foregroundStyle(by: .value("Category", point.label))
                    .cornerRadius(4)
                }
                .chartForegroundStyleScale(range: chartColors.prefix(payload.data.count).map { $0 })
                .chartLegend(.hidden)

                // Center total
                VStack(spacing: 2) {
                    Text(formatValue(payload.data.reduce(0) { $0 + $1.value }))
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundStyle(JarvisColors.textPrimary)
                    Text("TOTAL")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(JarvisColors.textDim)
                }
            }
            .frame(width: 200, height: 200)

            chartLegend
        }
        .frame(minHeight: 220)
    }

    // MARK: - Scatter Chart

    private var scatterChart: some View {
        Chart(Array(payload.data.enumerated()), id: \.element.id) { index, point in
            PointMark(
                x: .value(payload.xLabel ?? "Index", index),
                y: .value(payload.yLabel ?? "Value", animateChart ? point.value : 0)
            )
            .foregroundStyle(JarvisColors.accent)
            .symbolSize(60)
        }
        .chartStyle()
        .frame(minHeight: 280)
    }

    // MARK: - Shared Legend

    private var chartLegend: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(payload.data.enumerated()), id: \.element.id) { index, point in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(chartColors[index % chartColors.count])
                        .frame(width: 12, height: 12)

                    Text(point.label)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(JarvisColors.textSecondary)

                    Spacer()

                    Text(formatValue(point.value))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(JarvisColors.textPrimary)
                }
            }
        }
        .frame(maxWidth: 200)
    }

    // MARK: - Helpers

    private func formatValue(_ value: Double) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", value / 1_000) }
        if value == value.rounded() { return String(format: "%.0f", value) }
        return String(format: "%.1f", value)
    }
}

// MARK: - Chart Style Extension

extension Chart {
    func chartStyle() -> some View {
        self
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(JarvisColors.textDim)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(JarvisColors.primary.opacity(0.08))
                    AxisValueLabel()
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(JarvisColors.textDim)
                }
            }
    }
}

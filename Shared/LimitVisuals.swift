import AppKit
import SwiftUI

enum CodexTheme {
    // Sampled from the Codex landing-page aurora supplied with the redesign brief.
    static let primary = Color(red: 104 / 255, green: 118 / 255, blue: 242 / 255)
    static let primaryLight = Color(red: 174 / 255, green: 190 / 255, blue: 1)
    static let mist = Color(red: 216 / 255, green: 228 / 255, blue: 1)
    static let ink = Color(red: 7 / 255, green: 11 / 255, blue: 35 / 255)
    static let inkLifted = Color(red: 19 / 255, green: 27 / 255, blue: 70 / 255)
    static let warning = Color(red: 1, green: 181 / 255, blue: 112 / 255)
    static let critical = Color(red: 1, green: 91 / 255, blue: 111 / 255)
    static let textPrimary = Color.white.opacity(0.96)
    static let textSecondary = Color(red: 218 / 255, green: 226 / 255, blue: 1).opacity(0.72)
    static let hairline = Color.white.opacity(0.12)

    static let signalGradient = LinearGradient(
        colors: [primaryLight, primary],
        startPoint: .leading,
        endPoint: .trailing
    )
}

enum CodexType {
    private static let hasOpenAISans = NSFont(name: "OpenAI Sans", size: 13) != nil

    static func font(
        size: CGFloat,
        weight: Font.Weight = .regular,
        relativeTo textStyle: Font.TextStyle = .body
    ) -> Font {
        if hasOpenAISans {
            return .custom("OpenAI Sans", size: size, relativeTo: textStyle).weight(weight)
        }
        return .system(size: size, weight: weight, design: .rounded)
    }

    static let hero = font(size: 28, weight: .semibold, relativeTo: .title)
    static let title = font(size: 16, weight: .semibold, relativeTo: .headline)
    static let body = font(size: 13, weight: .medium)
    static let caption = font(size: 11, weight: .medium, relativeTo: .caption)
    static let micro = font(size: 9, weight: .semibold, relativeTo: .caption2)
}

enum LimitPalette {
    static func color(for remaining: Int) -> Color {
        switch remaining {
        case 26...: CodexTheme.primaryLight
        case 10..<26: CodexTheme.warning
        default: CodexTheme.critical
        }
    }

    static func gradient(for remaining: Int) -> LinearGradient {
        if remaining > 25 {
            return CodexTheme.signalGradient
        }
        let stateColor = color(for: remaining)
        return LinearGradient(
            colors: [stateColor.opacity(0.72), stateColor],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

struct CodexAuroraBackground: View {
    var body: some View {
        ZStack {
            CodexTheme.ink

            LinearGradient(
                colors: [
                    CodexTheme.ink,
                    CodexTheme.inkLifted.opacity(0.94),
                    Color(red: 30 / 255, green: 38 / 255, blue: 99 / 255)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [CodexTheme.primary.opacity(0.62), .clear],
                center: UnitPoint(x: 1.05, y: -0.08),
                startRadius: 0,
                endRadius: 260
            )

            RadialGradient(
                colors: [Color(red: 59 / 255, green: 91 / 255, blue: 210 / 255).opacity(0.28), .clear],
                center: UnitPoint(x: -0.1, y: 1.08),
                startRadius: 0,
                endRadius: 240
            )

            LinearGradient(
                colors: [.white.opacity(0.075), .clear, .white.opacity(0.025)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

struct CodexGlassCard<Content: View>: View {
    private let cornerRadius: CGFloat
    private let content: Content

    init(cornerRadius: CGFloat = 14, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.072))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.2), CodexTheme.primary.opacity(0.14), .white.opacity(0.06)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.8
                            )
                    }
                    .shadow(color: .black.opacity(0.22), radius: 12, y: 7)
            }
    }
}

struct CodexAccountGlyph: View {
    var size: CGFloat = 24

    var body: some View {
        ZStack {
            Circle()
                .fill(CodexTheme.signalGradient)
                .shadow(color: CodexTheme.primary.opacity(0.48), radius: size * 0.3)
            Image(systemName: "terminal.fill")
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.96))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct CodexLimitTrack: View {
    let remaining: Int
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.14))

                Capsule()
                    .fill(LimitPalette.gradient(for: remaining))
                    .frame(width: max(0, proxy.size.width * CGFloat(remaining) / 100))
                    .shadow(color: LimitPalette.color(for: remaining).opacity(0.52), radius: 5)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

struct LimitRing: View {
    let window: CodexLimitWindow
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 4 : 7) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.035))

                Circle()
                    .stroke(Color.white.opacity(0.11), lineWidth: compact ? 7 : 9)

                Circle()
                    .trim(from: 0, to: CGFloat(window.remainingPercent) / 100)
                    .stroke(
                        AngularGradient(
                            colors: ringColors,
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: compact ? 7 : 9, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: LimitPalette.color(for: window.remainingPercent).opacity(0.58), radius: 7)

                VStack(spacing: -1) {
                    Text("\(window.remainingPercent)%")
                        .font(compact ? CodexType.font(size: 22, weight: .semibold, relativeTo: .title3) : CodexType.hero)
                        .monospacedDigit()
                        .minimumScaleFactor(0.72)
                        .lineLimit(1)
                    Text("LEFT")
                        .font(CodexType.micro)
                        .tracking(0.9)
                        .foregroundStyle(CodexTheme.textSecondary)
                }
            }
            .aspectRatio(1, contentMode: .fit)

            Text(window.title.uppercased())
                .font(CodexType.micro)
                .tracking(1.1)
                .foregroundStyle(CodexTheme.textPrimary)
                .lineLimit(1)

            if let reset = window.resetsAt {
                Text(reset, style: .relative)
                    .font(CodexType.caption)
                    .monospacedDigit()
                    .foregroundStyle(CodexTheme.textSecondary)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(CodexTheme.textPrimary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(window.title), \(window.remainingPercent) percent remaining")
    }

    private var ringColors: [Color] {
        let color = LimitPalette.color(for: window.remainingPercent)
        return window.remainingPercent > 25
            ? [CodexTheme.primary, CodexTheme.primaryLight, CodexTheme.primary]
            : [color.opacity(0.66), color, color.opacity(0.66)]
    }
}

struct EmptyLimitView: View {
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(CodexTheme.primary.opacity(0.16))
                    .frame(width: 48, height: 48)
                Image(systemName: "waveform.path.ecg")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(CodexTheme.primaryLight)
            }
            Text(message)
                .font(CodexType.body)
                .multilineTextAlignment(.center)
            Text("OPEN CODEX LIMITS TO SYNC")
                .font(CodexType.micro)
                .tracking(0.7)
                .foregroundStyle(CodexTheme.textSecondary)
        }
        .foregroundStyle(CodexTheme.textPrimary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CodexUsagePulse: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let usage: CodexUsageSnapshot
    let weekOffset: Int
    var showsChart = true
    var compact = false
    var horizontal = false

    var body: some View {
        if let week = usage.week(offset: weekOffset) {
            Group {
                if horizontal, showsChart {
                    HStack(spacing: 8) {
                        summary(for: week)
                            .frame(width: 138)
                        UsageBarChart(week: week, compact: true)
                    }
                } else {
                    VStack(spacing: compact ? 6 : 8) {
                        summary(for: week)
                        if showsChart {
                            UsageBarChart(week: week, compact: compact)
                        }
                    }
                }
            }
            .padding(horizontal ? 6 : compact ? 7 : 9)
            .background(Color.black.opacity(0.11), in: RoundedRectangle(cornerRadius: compact ? 11 : 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: compact ? 11 : 13, style: .continuous)
                    .stroke(CodexTheme.hairline, lineWidth: 0.7)
            }
            .animation(
                reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 1),
                value: weekOffset
            )
        }
    }

    private func summary(for week: CodexUsageWeek) -> some View {
        HStack(spacing: 0) {
            UsageSummaryMetric(
                label: week.isCurrentWeek ? "TODAY" : "WEEK TOTAL",
                value: CodexUsageFormatting.tokenLabel(
                    week.isCurrentWeek ? week.todayTokens : week.totalTokens
                ),
                compact: compact
            )

            Rectangle()
                .fill(CodexTheme.hairline)
                .frame(width: 1, height: compact ? 22 : 27)
                .padding(.horizontal, compact ? 8 : 12)

            UsageSummaryMetric(
                label: week.isCurrentWeek ? "STREAK" : "PEAK DAY",
                value: week.isCurrentWeek
                    ? streakLabel(week.currentStreakDays)
                    : CodexUsageFormatting.tokenLabel(week.peakTokens),
                compact: compact
            )
        }
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, horizontal ? 4 : compact ? 6 : 8)
        .background(
            CodexTheme.inkLifted.opacity(0.78),
            in: RoundedRectangle(cornerRadius: compact ? 9 : 11, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 9 : 11, style: .continuous)
                .stroke(CodexTheme.primaryLight.opacity(0.13), lineWidth: 0.7)
        }
    }

    private func streakLabel(_ streak: Int64?) -> String {
        guard let streak else { return "—" }
        return "\(streak) DAY\(streak == 1 ? "" : "S")"
    }
}

struct CodexUsageInlineSummary: View {
    let usage: CodexUsageSnapshot
    let weekOffset: Int

    var body: some View {
        if let week = usage.week(offset: weekOffset) {
            HStack(spacing: 5) {
                inlineMetric(
                    label: week.isCurrentWeek ? "TODAY" : "WEEK",
                    value: CodexUsageFormatting.tokenLabel(
                        week.isCurrentWeek ? week.todayTokens : week.totalTokens
                    )
                )
                Text("/")
                    .foregroundStyle(CodexTheme.primaryLight.opacity(0.5))
                inlineMetric(
                    label: week.isCurrentWeek ? "STREAK" : "PEAK",
                    value: week.isCurrentWeek
                        ? "\(week.currentStreakDays ?? 0)D"
                        : CodexUsageFormatting.tokenLabel(week.peakTokens)
                )
            }
            .font(CodexType.micro)
            .tracking(0.25)
            .foregroundStyle(CodexTheme.textSecondary)
            .accessibilityElement(children: .combine)
        }
    }

    private func inlineMetric(label: String, value: String) -> some View {
        HStack(spacing: 2) {
            Text(label)
            Text(value)
                .foregroundStyle(CodexTheme.primaryLight)
        }
    }
}

private struct UsageSummaryMetric: View {
    let label: String
    let value: String
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(CodexType.micro)
                .tracking(0.7)
                .foregroundStyle(CodexTheme.textSecondary)
            Text(value)
                .font(compact ? CodexType.micro : CodexType.caption)
                .monospacedDigit()
                .foregroundStyle(CodexTheme.primaryLight)
                .lineLimit(1)
                .allowsTightening(true)
                .minimumScaleFactor(0.62)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct UsageBarChart: View {
    let week: CodexUsageWeek
    let compact: Bool

    private let calendar = Calendar.autoupdatingCurrent

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = compact ? 3 : 4
            let barWidth = max(2, (proxy.size.width - spacing * 6) / 7)
            HStack(alignment: .bottom, spacing: compact ? 3 : 4) {
                ForEach(week.days) { day in
                    let future = calendar.compare(day.date, to: .now, toGranularity: .day) == .orderedDescending
                    let highlighted = isHighlighted(day)
                    Capsule()
                        .fill(barStyle(future: future, highlighted: highlighted))
                        .frame(height: barHeight(day.tokens, availableHeight: proxy.size.height, future: future))
                        .shadow(
                            color: highlighted ? CodexTheme.primaryLight.opacity(0.58) : .clear,
                            radius: highlighted ? 4 : 0
                        )
                        .frame(width: barWidth, alignment: .bottom)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            "\(day.date.formatted(date: .complete, time: .omitted)), \(day.tokens.formatted()) tokens"
                        )
                }
            }
        }
        .frame(height: compact ? 25 : 34)
    }

    private func isHighlighted(_ day: CodexUsageWeek.Day) -> Bool {
        if week.isCurrentWeek {
            return calendar.isDateInToday(day.date)
        }
        return week.peakTokens > 0 && day.tokens == week.peakTokens
    }

    private func barHeight(_ tokens: Int64, availableHeight: CGFloat, future: Bool) -> CGFloat {
        guard !future, tokens > 0, week.peakTokens > 0 else { return 3 }
        let fraction = CGFloat(tokens) / CGFloat(week.peakTokens)
        return max(5, availableHeight * fraction)
    }

    private func barStyle(future: Bool, highlighted: Bool) -> AnyShapeStyle {
        if future {
            return AnyShapeStyle(Color.white.opacity(0.07))
        }
        if highlighted {
            return AnyShapeStyle(CodexTheme.signalGradient)
        }
        return AnyShapeStyle(CodexTheme.primaryLight.opacity(0.52))
    }
}

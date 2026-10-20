import SwiftUI
import Foundation

/// Элементы стиля карточки LIMITS из dsh-usage-hq, общие для приложения и
/// виджекта: формат процента, пороги цвета бара и сам тонкий капсульный бар.
/// Пороги DSH: обычный расход — нейтральная заливка, ≥70 — янтарный, ≥90 —
/// красный. Зелёный не используется: у DSH обычное заполнение нейтральное.

/// Формат процента как в DSH: ≥10 — целое, <10 — один знак (8.5%).
public func usagePercentText(_ percent: Double) -> String {
    percent >= 10 ? "\(Int(percent.rounded()))%" : String(format: "%.1f%%", percent)
}

/// Оттенок бара DSH: обычный — нейтральный, ≥70 — янтарный, ≥90 — красный.
public func usageBarTint(_ percent: Double) -> Color {
    if percent >= 90 { return .red }
    if percent >= 70 { return .orange }
    return .primary.opacity(0.55)
}

/// Схлопывание окон-дублей для отображения (например, «Monthly» и
/// «Monthly (code)» у Kimi — одно и то же месячное окно из limits[] и
/// usages[]): нормализованная подпись без содержимого скобок, регистр не
/// важен; остаётся ПЕРВОЕ вхождение (limits[] задокументированно старше).
public func dedupeUsageWindows(_ windows: [UsageWindow]) -> [UsageWindow] {
    var seen = Set<String>()
    return windows.filter { window in
        let label = (window.name ?? window.key).lowercased()
        let base = label.prefix(while: { $0 != "(" }).trimmingCharacters(in: .whitespaces)
        return seen.insert(base).inserted
    }
}

/// Подпись окна для отображения: имя провайдера («Monthly») приводится к
/// строчной первой букве — ключи («week», «5h») уже строчные (стиль DSH).
public func usageWindowLabel(_ window: UsageWindow) -> String {
    let raw = window.name ?? window.key
    guard let first = raw.first else { return raw }
    return first.lowercased() + raw.dropFirst()
}

/// Обратный отсчёт до сброса окна в формате «дни часы минуты»: «5д 8ч»,
/// «4ч 16м», «12м». nil — сброс в прошлом или время не разобралось
/// (истёкшее окно не изображается идущим отсчётом).
public func usageResetCountdown(resetsAtISO: String, now: Date = Date()) -> String? {
    guard let date = parseNormalizedISO(resetsAtISO) else { return nil }
    let interval = date.timeIntervalSince(now)
    guard interval > 0 else { return nil }
    let totalMinutes = Int(interval / 60)
    let days = totalMinutes / (24 * 60)
    let hours = (totalMinutes % (24 * 60)) / 60
    let minutes = totalMinutes % 60
    if days > 0 { return "\(days)д \(hours)ч" }
    if hours > 0 { return "\(hours)ч \(minutes)м" }
    return "\(max(minutes, 1))м"
}


/// Тонкий капсульный бар в стиле DSH: нейтральный трек 10%, заполнение по
/// порогу. Высота настраивается (5 в панели, 4 в виджете).
public struct ThinUsageBar: View {
    let percent: Double
    let height: CGFloat

    public init(percent: Double, height: CGFloat = 5) {
        self.percent = percent
        self.height = height
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.10))
                Capsule()
                    .fill(usageBarTint(percent))
                    .frame(width: max(2, geo.size.width * min(max(percent, 0), 100) / 100))
            }
        }
        .frame(height: height)
    }
}

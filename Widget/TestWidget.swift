import SwiftUI
import UsageCore
import WidgetKit

// Quick 261018-jd8 (WIDG-01, D-11 снята): продуктовый виджет на общем снимке.
// Kind НЕ меняется (testWidgetKind — те же литералы «AiUsageTestWidget» в
// StaticConfiguration и reloadTimelines приложения) — уже размещённые виджеты
// выживают обновление. Расширение ТОЛЬКО ЧИТАЕТ usage-snapshot.json из
// контейнера группы: без сети, без Keychain, без записей и без таймеров вне
// таймлайна WidgetKit. Возраст обновляется нативным Text(_, style: .relative).

@main
struct TestWidgetBundle: WidgetBundle {
    var body: some Widget {
        TestWidget()
    }
}

// MARK: - Timeline

struct UsageEntry: TimelineEntry {
    let date: Date
    let state: UsageSnapshotState
}

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        // Плейсхолдер честен: «нет данных», без выдуманных процентов (D-07).
        UsageEntry(date: Date(), state: .missing)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(UsageEntry(date: Date(), state: currentState()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let now = Date()
        let entry = UsageEntry(date: now, state: currentState())
        // Основной путь обновления — reload из активного приложения (бесплатно);
        // фоновый запасной перезапрос — не раньше чем через 15 минут.
        let timeline = Timeline(entries: [entry], policy: .after(now.addingTimeInterval(15 * 60)))
        completion(timeline)
    }

    /// Чтение контейнера (только чтение): доступность проверяется листингом
    /// каталога; ENOENT → missing; I/O → unavailable; decode/версия → corrupt.
    private func currentState() -> UsageSnapshotState {
        guard let groupID = appGroupID(from: .main),
              let directory = FileManager.default
                  .containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
            return .unavailable
        }
        guard (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) != nil else {
            return .unavailable
        }
        return SnapshotStore(directory: directory).read()
    }
}

// MARK: - Виджет

struct TestWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: testWidgetKind, provider: UsageProvider()) { entry in
            TestWidgetView(entry: entry)
        }
        .configurationDisplayName("AI Usage")
        .description("Расход лимитов AI-подписок")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - View

struct TestWidgetView: View {
    let entry: UsageEntry

    var body: some View {
        content
            // Гарантированные 24 часа без AM/PM независимо от системной локали.
            .environment(\.locale, Locale(identifier: "ru_RU"))
    }

    @ViewBuilder
    private var content: some View {
        switch entry.state {
        case .snapshot(let snapshot):
            WidgetContentView(snapshot: snapshot)
        case .missing:
            statusView(title: "Подключите аккаунты",
                       subtitle: "Введите ключи в настройках приложения")
        case .corrupt:
            statusView(title: "Кэш повреждён",
                       subtitle: "Откройте приложение и обновите данные")
        case .unavailable:
            statusView(title: "Общая папка недоступна",
                       subtitle: "Проверьте App Group в приложении")
        }
    }

    private func statusView(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
                .minimumScaleFactor(0.6)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            Rectangle().fill(.windowBackground)
        }
    }
}

/// Провайдерские строки из снимка.
struct WidgetContentView: View {
    let snapshot: UsageSnapshot
    @Environment(\.widgetFamily) private var family

    private var subscriptions: [ProviderRow] {
        snapshot.rows
            .filter { !$0.providerID.isBalanceProvider }
            .sorted { $0.providerID.displayOrder < $1.providerID.displayOrder }
    }

    private var balances: [ProviderRow] {
        snapshot.rows
            .filter { $0.providerID.isBalanceProvider }
            .sorted { $0.providerID.displayOrder < $1.providerID.displayOrder }
    }

    /// Часы карточки DSH: возраст самых свежих фактов (одна строка вместо
    /// шума в каждой строке; fetchedAt у строк одного прохода совпадает).
    private var freshestFetchedAt: Date? {
        snapshot.rows.compactMap(\.fetchedAt).max()
    }

    var body: some View {
        // Валидный, но пустой снимок (ничего не подключено) — то же честное
        // «Подключите аккаунты», что и отсутствующий файл; никаких нулей (D-07).
        if snapshot.rows.isEmpty {
            emptyView
        } else {
            switch family {
            case .systemSmall:
                smallView
            default:
                mediumView
            }
        }
    }

    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Подключите аккаунты")
                .font(.headline)
                .minimumScaleFactor(0.6)
            Text("Введите ключи в настройках приложения")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            Rectangle().fill(.windowBackground)
        }
    }

    // MARK: Small: гланс LIMITS — имя + значение + тонкий бар (как foot-card)

    /// Фиксированный порядок владельца (Codex → GLM → Kimi → балансы),
    /// не ранжирование по худшему окну.
    private var smallRows: [ProviderRow] {
        (subscriptions + balances)
            .sorted { $0.providerID.displayOrder < $1.providerID.displayOrder }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 4) {
            limitHeader(fontSize: 8)
            ForEach(smallRows) { row in
                SmallProviderRow(row: row)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            Rectangle().fill(.windowBackground)
        }
    }

    /// Шапка DSH: крошечный LIMITS + возраст свежих фактов справа.
    @ViewBuilder
    private func limitHeader(fontSize: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("LIMITS")
                .font(.system(size: fontSize, weight: .semibold))
                .tracking(0.06)
                .opacity(0.5)
            Spacer(minLength: 4)
            if let fetchedAt = freshestFetchedAt {
                Text(fetchedAt, style: .relative)
                    .font(.system(size: fontSize))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Medium: блоки подписок с окнами (PlanCard) + колонка балансов

    private var mediumView: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                limitHeader(fontSize: 8)
                ForEach(subscriptions) { row in
                    MediumSubscriptionBlock(row: row)
                }
                Spacer(minLength: 0)
            }
            // Балансы: узкая правая колонка за тонкой чертой (PAYG-блок DSH).
            // Черта фиксированной ширины, баланс прижат к ВЕРХУ — раньше
            // растянутый разделитель уносил балансы в низ виджета.
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(.primary.opacity(0.15))
                    .frame(width: 1)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(balances) { row in
                        MediumBalanceRow(row: row)
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .frame(width: 92)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            Rectangle().fill(.windowBackground)
        }
    }

    /// Осмысленные цвета: пороги DSH из UsageCore.usageBarTint.
    static func tint(_ percent: Double) -> Color {
        usageBarTint(percent)
    }
}

/// Строка small: имя + значение, под процентами тонкий бар DSH.
/// WR-03: неизвестные окна видны бейджем «неизв.» и прочерком; известный
/// максимум при неполноте НЕ окрашивается как «всё хорошо».
struct SmallProviderRow: View {
    let row: ProviderRow

    private var dominantPercent: Double? {
        row.windows.compactMap(\.percent).max()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                ProviderLogo(provider: row.providerID, size: 10)
                Text(row.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 2)
                if containsUnknownPercent(row.windows) {
                    Text("неизв.")
                        .font(.system(size: 8))
                        .foregroundStyle(.orange)
                }
                if let currency = row.balanceCurrency, let total = row.balanceTotal {
                    Text("\(total) \(currency)")
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                } else if let percent = dominantPercent {
                    Text(usagePercentText(percent))
                        .font(.system(size: 11, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(containsUnknownPercent(row.windows) ? .secondary : usageBarTint(percent))
                } else if !row.windows.isEmpty {
                    Text("—")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                if row.error != nil && row.fetchedAt == nil {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 8))
                        .foregroundStyle(.yellow)
                }
            }
            if let percent = dominantPercent {
                ThinUsageBar(percent: percent, height: 3)
            }
            if row.error != nil && row.fetchedAt == nil {
                Text(row.error ?? "")
                    .font(.system(size: 8))
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
    }
}

/// Блок подписки medium (как PlanCard DSH): имя + доминирующий процент,
/// под ним по строке на окно: подпись + тонкий бар + процент; сброс мелко.
struct MediumSubscriptionBlock: View {
    let row: ProviderRow

    private var dominantPercent: Double? {
        row.windows.compactMap(\.percent).max()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                ProviderLogo(provider: row.providerID, size: 11)
                Text(row.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 2)
                if containsUnknownPercent(row.windows) {
                    Text("неизв.")
                        .font(.system(size: 8))
                        .foregroundStyle(.orange)
                }
                if let percent = dominantPercent {
                    Text(usagePercentText(percent))
                        .font(.system(size: 11, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(containsUnknownPercent(row.windows) ? .secondary : usageBarTint(percent))
                } else if !row.windows.isEmpty {
                    Text("—").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                if row.error != nil {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 8))
                        .foregroundStyle(.yellow)
                }
            }
            // Дубли окон («Monthly» / «Monthly (code)») схлопываются в одну шкалу.
            ForEach(Array(dedupeUsageWindows(row.windows).enumerated()), id: \.offset) { _, window in
                mediumWindowRow(window)
            }
            if let error = row.error, row.fetchedAt == nil {
                Text(error)
                    .font(.system(size: 8))
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
    }

    /// Строка окна: подпись строчной буквой (стиль DSH), бар, процент, отсчёт.
    @ViewBuilder
    private func mediumWindowRow(_ window: UsageWindow) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline) {
                Text(usageWindowLabel(window))
                    .font(.system(size: 9))
                    .opacity(0.7)
                if let countdown = window.resetsAt.flatMap({ usageResetCountdown(resetsAtISO: $0) }) {
                    Text("сброс \(countdown)")
                        .font(.system(size: 8, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 2)
                if let percent = window.percent {
                    Text(usagePercentText(percent))
                        .font(.system(size: 9, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(usageBarTint(percent))
                } else {
                    Text("—")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            if let percent = window.percent {
                ThinUsageBar(percent: percent, height: 3)
            }
        }
    }
}

/// Строка баланса medium: логотип, имя сверху, значение жирным под ним.
struct MediumBalanceRow: View {
    let row: ProviderRow

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                ProviderLogo(provider: row.providerID, size: 10)
                Text(row.displayName)
                    .font(.system(size: 9))
                    .opacity(0.7)
                    .lineLimit(1)
            }
            if let currency = row.balanceCurrency, let total = row.balanceTotal {
                Text("\(total) \(currency)")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
            } else {
                Text("—")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if let error = row.error {
                Text(error)
                    .font(.system(size: 8))
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
    }
}

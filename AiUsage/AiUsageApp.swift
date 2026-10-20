import SwiftUI
import UsageCore

// Quick 261018-jd8 (MENU-01/MENU-02): продуктовый дашборд меню-бара.
// TestPanelView/кнопка «Записать тест» убраны из UI (TestRecord.swift и его
// тесты остаются в пакете — история фазы 1). Приложение — единственный писатель
// снимка; модель UsageModel живёт вместе с приложением (Task 2).

@main
struct AiUsageApp: App {
    @State private var model: UsageModel

    init() {
        // Узкий самопроверочный режим (signed sandbox, классический macOS
        // keychain): случайный fixture-слот, фиксированный PASS/FAIL с числовым
        // OSStatus в stdout, выход ДО создания модели и любой сети. Реальные
        // слоты провайдеров и токены не читаются; логов секретов нет.
        if ProcessInfo.processInfo.arguments.contains("--self-test-keychain") {
            exit(KeychainSelfTest.run())
        }
        if ProcessInfo.processInfo.arguments.contains("--import-credentials-stdin") {
            // Run the async one-shot BEFORE SwiftUI scenes or activate/timer.
            // The main run loop services URLSession/MainActor until exit.
            let cliModel = UsageModel()
            Task { @MainActor in
                exit(await CredentialStdinImport.run(model: cliModel))
            }
            RunLoop.main.run()
            exit(1)
        }
        if ProcessInfo.processInfo.arguments.contains("--debug-shape") {
            // Диагностика ФОРМЫ ответов провайдеров: значения заменяются типами,
            // токены и данные не печатаются. Одноразовый CLI без записи кэша.
            let cliModel = UsageModel()
            Task { @MainActor in
                exit(await cliModel.debugShapeMain())
            }
            RunLoop.main.run()
            exit(1)
        }
        let model = UsageModel()
        // Старт при запуске приложения, НЕ при открытии popover: загрузка
        // last-good, первый проход, далее таймер 5 минут (UsageModel.activate).
        model.activate()
        _model = State(initialValue: model)
    }

    var body: some Scene {
        MenuBarExtra("AI Usage", systemImage: "gauge") {
            DashboardView(model: model)
                .environment(\.locale, Locale(identifier: "ru_RU"))
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
                .environment(\.locale, Locale(identifier: "ru_RU"))
        }
    }
}

// MARK: - Дашборд в стиле карточки LIMITS из dsh-usage-hq:
// тихая карточка 12pt радиус, нейтральные тонкие бары (не зелёные),
// доминирующий процент справа от имени, окна со сбросом, балансы за
// тонким разделителем. Общие помощники стиля — в UsageCore (UsageStyle.swift).

struct DashboardView: View {
    let model: UsageModel

    private var subscriptionRows: [ProviderRow] {
        model.orderedRows
            .filter { !$0.providerID.isBalanceProvider }
            .sorted { $0.providerID.displayOrder < $1.providerID.displayOrder }
    }

    private var balanceRows: [ProviderRow] {
        model.orderedRows
            .filter { $0.providerID.isBalanceProvider }
            .sorted { $0.providerID.displayOrder < $1.providerID.displayOrder }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            VStack(alignment: .leading, spacing: 10) {
                header
                if model.orderedRows.isEmpty {
                    emptyState
                } else {
                    // Одна тихая карточка: подписки, тонкая черта, балансы.
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(subscriptionRows) { row in
                            ProviderBlockView(row: row)
                        }
                        if !balanceRows.isEmpty {
                            Divider().opacity(0.6)
                            ForEach(balanceRows) { row in
                                BalanceRowView(row: row)
                            }
                        }
                    }
                    .padding(12)
                    .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(12)
            .frame(width: 340)
            .background(.regularMaterial)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "gauge")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("LIMITS")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.06)
                .textCase(.uppercase)
                .opacity(0.6)
            Spacer()
            if let updated = model.orderedRows.compactMap(\.fetchedAt).max() {
                Text(updated, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help("Возраст самых свежих фактов")
            }
            if model.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    Task { await model.refreshNow() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("Обновить сейчас")
            }
        }
    }

    /// Пусто — честное «Подключите аккаунты»: никаких нулей и демо-строк (D-07).
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Подключите аккаунты")
                .font(.headline)
            Text("Откройте настройки и введите ключи провайдеров или импортируйте auth.json.")
                .font(.caption)
                .foregroundStyle(.secondary)
            OpenSettingsButton()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

/// Кнопка вызова штатных настроек (только из действия пользователя).
struct OpenSettingsButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Настройки…") {
            openSettings()
        }
    }
}

// MARK: - Блок провайдера (как PlanCard в DSH): имя + доминирующий процент,
// под ним строки окон с тонкими барами и временем сброса.

struct ProviderBlockView: View {
    let row: ProviderRow

    /// Доминирующий (худший) процент строки; nil — все окна неизвестны.
    private var dominantPercent: Double? {
        row.windows.compactMap(\.percent).max()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                ProviderLogo(provider: row.providerID, size: 12)
                Text(row.displayName)
                    .font(.system(size: 13, weight: .semibold))
                if let planName = row.planName {
                    Text("· \(planName)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if row.error != nil {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 10))
                        .foregroundStyle(.yellow)
                        .help(row.error ?? "")
                }
                Spacer()
                if containsUnknownPercent(row.windows) {
                    Text("неизв.")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
                if let percent = dominantPercent {
                    Text(usagePercentText(percent))
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(containsUnknownPercent(row.windows) ? .secondary : usageBarTint(percent))
                } else if !row.windows.isEmpty {
                    Text("—")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            // Дубли окон («Monthly» / «Monthly (code)») схлопываются в одну шкалу.
            ForEach(Array(dedupeUsageWindows(row.windows).enumerated()), id: \.offset) { _, window in
                WindowRowView(window: window)
            }
            // Возраст данных — один раз в шапке (LIMITS); здесь только
            // состояние без фактов и текст ошибки.
            if let error = row.error {
                HStack(spacing: 6) {
                    if row.fetchedAt == nil {
                        Text("данных ещё нет")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }
        }
    }
}

/// Строка окна DSH: подпись + процент справа, тонкий бар 5px, сброс мелко.
struct WindowRowView: View {
    let window: UsageWindow

    private var title: String {
        usageWindowLabel(window)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.system(size: 12))
                    .opacity(0.8)
                Spacer()
                if let percent = window.percent {
                    Text(usagePercentText(percent))
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(usageBarTint(percent))
                } else {
                    Text("—")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            if let percent = window.percent {
                ThinUsageBar(percent: percent)
            }
            if let resetsAt = window.resetsAt,
               let countdown = usageResetCountdown(resetsAtISO: resetsAt) {
                Text("сброс через \(countdown)")
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Строка баланса (как в карточке балансов DSH): имя слева, значение справа.
struct BalanceRowView: View {
    let row: ProviderRow

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                ProviderLogo(provider: row.providerID, size: 11)
                Text(row.displayName)
                    .font(.system(size: 13))
                Spacer()
                if let currency = row.balanceCurrency, let total = row.balanceTotal {
                    // Баланс — сумма и валюта, не проценты.
                    Text("\(total) \(currency)")
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                } else {
                    Text("—")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                if row.error != nil {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 10))
                        .foregroundStyle(.yellow)
                        .help(row.error ?? "")
                }
            }
            if let error = row.error {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
        .opacity(row.error != nil && row.fetchedAt == nil ? 0.7 : 1)
    }
}

// MARK: - Настройки (SecureField → Keychain; импорт auth.json; GLM-регион)

struct SettingsView: View {
    let model: UsageModel

    private enum GlmOrigin: String, CaseIterable, Identifiable {
        case cn = "open.bigmodel.cn (Китай)"
        case intl = "api.z.ai (международный)"
        var id: String { rawValue }
    }

    @State private var glmOrigin: GlmOrigin = .cn
    @State private var kimiKey = ""
    @State private var glmKey = ""
    @State private var openRouterKey = ""
    @State private var deepSeekKey = ""

    var body: some View {
        Form {
            importSection
            keySection("Kimi", provider: .kimi, key: $kimiKey)
            glmSection
            keySection("OpenRouter", provider: .openrouter, key: $openRouterKey)
            keySection("DeepSeek", provider: .deepseek, key: $deepSeekKey)
            codexSection
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 520)
    }

    private var importSection: some View {
        Section {
            Button("Импорт из файла (Codex / Kilo)…") {
                if let imported = CredentialFilePicker.pickAndParse() {
                    model.applyImport(imported)
                }
            }
            Text("Выберите auth.json (⌘⇧G для ввода пути). Файл только читается; refresh-токены не сохраняются. Ключ Codex подключается только этим импортом.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let summary = model.lastImportSummary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let keychainError = model.lastKeychainError {
                Text(keychainError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Импорт")
        }
    }

    /// Поле ключа: SecureField, запись ТОЛЬКО по кнопке «Сохранить» (поле
    /// очищается только при подтверждённом успехе записи); удаление убирает
    /// только этот аккаунт и его строку.
    private func keySection(_ title: String, provider: ProviderID, key: Binding<String>) -> some View {
        Section(title) {
            HStack {
                SecureField("Ключ API", text: key)
                Button("Сохранить") {
                    if model.saveCredential(provider, token: key.wrappedValue) {
                        key.wrappedValue = ""
                    }
                }
                .disabled(key.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            statusRow(provider)
        }
    }

    /// GLM: селектор РЕГИОНА из двух фиксированных origin — произвольный хост
    /// не вводится (токен не уходит на несуществующий регион).
    private var glmSection: some View {
        Section("GLM") {
            Picker("Регион", selection: $glmOrigin) {
                ForEach(GlmOrigin.allCases) { origin in
                    Text(origin.rawValue).tag(origin)
                }
            }
            HStack {
                SecureField("Ключ (без Bearer)", text: $glmKey)
                Button("Сохранить") {
                    let provider: ProviderID = glmOrigin == .cn ? .glmCN : .glmIntl
                    if model.saveCredential(provider, token: glmKey) {
                        glmKey = ""
                    }
                }
                .disabled(glmKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            statusRow(.glmCN)
            statusRow(.glmIntl)
        }
    }

    private var codexSection: some View {
        Section("Codex (подписка ChatGPT)") {
            statusRow(.codex)
            if model.providerPresence(.codex) == .needsReimport {
                // Канонического конверта нет, но обнаружены legacy-слоты v3–v5:
                // они НЕ угадываются и НЕ смешиваются — только явный реимпорт.
                Text("Обнаружено сохранение старого формата. Оно не используется: импортируйте auth.json заново кнопкой выше — запись выполнится одной атомарной операцией.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Button("Отключить") { model.disconnect(.codex) }
                .disabled(model.providerPresence(.codex) == .absent)
            Text("Подключение — импортом auth.json (кнопка выше). Если строка показывает «HTTP 401», запустите Codex CLI один раз и импортируйте файл заново.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Статус по факту присутствия слота: present/absent/unavailable/
    /// needsReimport различаются — недоступная Keychain не показывается как
    /// «Не подключён» (FIX5), legacy-пара Codex — как «подключён» (CR-02).
    private func statusRow(_ provider: ProviderID) -> some View {
        let presence = model.providerPresence(provider)
        let label: String
        switch presence {
        case .present: label = "Подключён"
        case .absent: label = "Не подключён"
        case .unavailable: label = "Keychain недоступна"
        case .needsReimport: label = "Требуется повторный импорт"
        }
        return HStack {
            Image(systemName: presence == .present ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(presence == .present ? .green
                                 : presence == .needsReimport ? .orange : .secondary)
            Text(label)
                .font(.caption)
            Spacer()
            // Отключение доступно при любом присутствии записи (включая legacy
            // Codex): удаляются и конверт, и свои legacy-слоты. При absent и
            // unavailable кнопки нет (отсутствие не подтверждено при отказе).
            if presence == .present || presence == .needsReimport {
                Button("Отключить", role: .destructive) {
                    model.disconnect(provider)
                }
                .controlSize(.small)
            }
        }
    }
}

// swift-tools-version: 6.0
// Локальный пакет UsageCore — общий код app-таргета и widget extension (фаза 1).
// Внешних зависимостей нет (стек целиком из состава SDK).
// Тесты Swift Testing добавляет план 01-02 (Tests/UsageCoreTests/TestRecordTests.swift).
import PackageDescription

let package = Package(
    name: "UsageCore",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "UsageCore", targets: ["UsageCore"])
    ],
    targets: [
        .target(name: "UsageCore"),
        // Тестовый таргет плана 01-02 (Tests/UsageCoreTests/TestRecordTests.swift):
        // состояния декодирования + allowlist Debug-инъекции.
        .testTarget(
            name: "UsageCoreTests",
            dependencies: ["UsageCore"]
        ),
    ]
)

import Testing
@testable import UsageCore

/// Логотипы: путь каждого разбора — непустой и почти на весь viewBox.
/// Дегенеративные границы означали обрыв неявного повторения команд SVG.
@MainActor
struct SVGPathParserTests {
    @Test func openAILogoCoversViewBox() {
        let rect = SVGPathParser.parse(ProviderLogo.openAIPath).boundingRect
        #expect(rect.width > 20 && rect.height > 22)
    }

    @Test func kimiLogoCoversViewBox() {
        let rect = SVGPathParser.parse(ProviderLogo.kimiPath).boundingRect
        #expect(rect.width > 20 && rect.height > 20)
    }

    @Test func openRouterLogoCoversViewBox() {
        let rect = SVGPathParser.parse(ProviderLogo.openRouterPath).boundingRect
        #expect(rect.width > 20 && rect.height > 20)
    }

    @Test func zaiCutoutsParse() {
        let rect = SVGPathParser.parse(ProviderLogo.zaiCutouts).boundingRect
        #expect(rect.width > 15 && rect.height > 13)
    }
}

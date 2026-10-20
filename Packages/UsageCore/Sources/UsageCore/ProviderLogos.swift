import SwiftUI

/// Логотипы провайдеров из dsh-usage-hq (UsageFootCard.providerLogo): те же
/// SVG-пути, отрисованные SwiftUI в currentColor. Значения путей скопированы
/// 1:1; рисование — через мини-парсер SVG path (M L H V C S Q T A Z, оба
/// регистра; дуги → кубические кривые по алгоритму спецификации SVG).

public struct ProviderLogo: View {
    let provider: ProviderID
    let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    public init(provider: ProviderID, size: CGFloat = 11) {
        self.provider = provider
        self.size = size
    }

    /// Canvas не разворачивает семантический .primary — передаём явный цвет темы.
    private var logoColor: Color {
        colorScheme == .dark ? .white : .black
    }

    public var body: some View {
        logo
            // ЕДИНАя привязка для всех логотипов: центр иконки чуть выше
            // базовой линии текста — иначе логотипы «танцуют» (внутренние
            // поля viewBox у разных знаков не совпадают).
            .frame(width: size, height: size)
            .alignmentGuide(.firstTextBaseline) { (dimensions: ViewDimensions) in
                dimensions.height * 0.8
            }
    }

    @ViewBuilder
    private var logo: some View {
        switch provider {
        case .codex:
            SVGPathShape(d: Self.openAIPath, viewBox: 24).fill(.primary)
        case .kimi:
            SVGPathShape(d: Self.kimiPath, viewBox: 24).fill(.primary)
        case .glmCN, .glmIntl:
            // Платформа Z: Canvas-слой с destinationOut — вырезы буквы Z
            // честно стирают заливку. Пути квадратa и вырезов живут в ОДНОЙ
            // системе координат viewBox: общий transform по объединённым
            // границам (раздельный фит ломал совпадение — «сплошной квадрат»).
            ZShapeView(square: Self.zaiSquare, cutouts: Self.zaiCutouts,
                       viewBox: 30, color: logoColor)
        case .openrouter:
            SVGPathShape(d: Self.openRouterPath, viewBox: 24).fill(.primary)
        case .deepseek:
            SVGPathShape(d: Self.deepSeekPath, viewBox: 24).fill(.primary)
        }
    }

    static let openAIPath = "M22.2819 9.8211a5.9847 5.9847 0 0 0-.5157-4.9108 6.0462 6.0462 0 0 0-6.5098-2.9A6.0651 6.0651 0 0 0 4.9807 4.1818a5.9847 5.9847 0 0 0-3.9977 2.9 6.0462 6.0462 0 0 0 .7427 7.0966 5.98 5.98 0 0 0 .511 4.9107 6.051 6.051 0 0 0 6.5146 2.9001A5.9847 5.9847 0 0 0 13.2599 24a6.0557 6.0557 0 0 0 5.7718-4.2058 5.9894 5.9894 0 0 0 3.9977-2.9001 6.0557 6.0557 0 0 0-.7475-7.0729zm-9.022 12.6081a4.4755 4.4755 0 0 1-2.8764-1.0408l.1419-.0804 4.7783-2.7582a.7948.7948 0 0 0 .3927-.6813v-6.7369l2.02 1.1686a.071.071 0 0 1 .038.052v5.5826a4.504 4.504 0 0 1-4.4945 4.4944zm-9.6607-4.1254a4.4708 4.4708 0 0 1-.5346-3.0137l.142.0852 4.783 2.7582a.7712.7712 0 0 0 .7806 0l5.8428-3.3685v2.3324a.0804.0804 0 0 1-.0332.0615L9.74 19.9502a4.4992 4.4992 0 0 1-6.1408-1.6464zM2.3408 7.8956a4.485 4.485 0 0 1 2.3655-1.9728V11.6a.7664.7664 0 0 0 .3879.6765l5.8144 3.3543-2.0201 1.1685a.0757.0757 0 0 1-.071 0l-4.8303-2.7865A4.504 4.504 0 0 1 2.3408 7.872zm16.5963 3.8558L13.1038 8.364 15.1192 7.2a.0757.0757 0 0 1 .071 0l4.8303 2.7913a4.4944 4.4944 0 0 1-.6765 8.1042v-5.6772a.79.79 0 0 0-.407-.667zm2.0107-3.0231l-.142-.0852-4.7735-2.7818a.7759.7759 0 0 0-.7854 0L9.409 9.2297V6.8974a.0662.0662 0 0 1 .0284-.0615l4.8303-2.7866a4.4992 4.4992 0 0 1 6.6802 4.66zM8.3065 12.863l-2.02-1.1638a.0804.0804 0 0 1-.038-.0567V6.0742a4.4992 4.4992 0 0 1 7.3757-3.4537l-.142.0805L8.704 5.459a.7948.7948 0 0 0-.3927.6813zm1.0976-2.3654l2.602-1.4998 2.6069 1.4998v2.9994l-2.5974 1.4997-2.6067-1.4997Z"
    static let kimiPath = "M21.765.351C22.998.351 24 1.353 24 2.586S22.998 4.82 21.765 4.82h-1.974c-.15 0-.26-.12-.26-.26V2.586A2.237 2.237 0 0 1 21.765.35M9.41 13.388l8.447-8.377c.16-.16.07-.471-.14-.471h-4.55s-.1.02-.14.06l-9.099 9.029c-.14.14-.35.02-.35-.21V4.81c0-.15-.1-.27-.221-.27H.22c-.12 0-.22.12-.22.27v18.57c0 .15.1.27.22.27h3.137c.12 0 .22-.12.22-.27v-3.79c0-.08.03-.16.08-.21l2.826-2.796c.07-.07.16-.08.241-.03l7.546 5.551a8.9 8.9 0 0 0 4.018 1.493c.12.01.23-.11.23-.27V19.76c0-.14-.08-.25-.19-.26a5.8 5.8 0 0 1-2.355-.942l-6.533-4.73c-.14-.09-.15-.32-.03-.441"
    static let openRouterPath = "M16.778 1.844v1.919q-.569-.026-1.138-.032-.708-.008-1.415.037c-1.93.126-4.023.728-6.149 2.237-2.911 2.066-2.731 1.95-4.14 2.75-.396.223-1.342.574-2.185.798-.841.225-1.753.333-1.751.333v4.229s.768.108 1.61.333c.842.224 1.789.575 2.185.799 1.41.798 1.228.683 4.14 2.75 2.126 1.509 4.22 2.11 6.148 2.236.88.058 1.716.041 2.555.005v1.918l7.222-4.168-7.222-4.17v2.176c-.86.038-1.611.065-2.278.021-1.364-.09-2.417-.357-3.979-1.465-2.244-1.593-2.866-2.027-3.68-2.508.889-.518 1.449-.906 3.822-2.59 1.56-1.109 2.614-1.377 3.978-1.466.667-.044 1.418-.017 2.278.02v2.176L24 6.014Z"
    static let deepSeekPath = "M23.748 4.651c-.254-.124-.364.113-.512.233-.051.04-.094.09-.137.137-.372.397-.806.657-1.373.626-.829-.046-1.537.214-2.163.848-.133-.782-.575-1.248-1.247-1.548-.352-.155-.708-.311-.955-.65-.172-.24-.219-.509-.305-.774-.055-.16-.11-.323-.293-.35-.2-.031-.278.136-.356.276-.313.572-.434 1.202-.422 1.84.027 1.436.633 2.58 1.838 3.393.137.094.172.187.129.323-.082.28-.18.553-.266.833-.055.179-.137.218-.328.14a5.5 5.5 0 0 1-1.737-1.179c-.857-.828-1.631-1.743-2.597-2.46a12 12 0 0 0-.689-.47c-.985-.957.13-1.743.387-1.836.27-.098.094-.433-.778-.428-.872.003-1.67.295-2.687.685a3 3 0 0 1-.465.136 9.6 9.6 0 0 0-2.883-.101c-1.885.21-3.39 1.1-4.497 2.622C.082 8.776-.231 10.854.152 13.02c.403 2.284 1.568 4.175 3.36 5.653 1.857 1.533 3.997 2.284 6.438 2.14 1.482-.085 3.132-.284 4.994-1.86.47.234.962.328 1.78.398.629.058 1.235-.031 1.705-.129.735-.155.684-.836.418-.961-2.155-1.004-1.682-.595-2.112-.926 1.095-1.295 2.768-3.598 3.284-6.733.05-.346.115-.834.108-1.114-.004-.171.035-.238.23-.257a4.2 4.2 0 0 0 1.545-.475c1.397-.763 1.96-2.016 2.093-3.517.02-.23-.004-.467-.247-.588M11.58 18.168c-2.088-1.642-3.101-2.183-3.52-2.16-.39.024-.32.472-.234.763.09.288.207.487.371.74.114.167.192.416-.113.603-.673.416-1.842-.14-1.897-.168-1.361-.801-2.5-1.86-3.301-3.306-.775-1.393-1.225-2.888-1.299-4.482-.02-.385.094-.522.477-.592a4.7 4.7 0 0 1 1.53-.038c2.131.311 3.946 1.264 5.467 2.774.868.86 1.525 1.887 2.202 2.89.72 1.066 1.494 2.082 2.48 2.915.348.291.626.513.892.677-.802.09-2.14.109-3.055-.615zm1.001-6.44a.306.306 0 0 1 .415-.287.3.3 0 0 1 .113.074.3.3 0 0 1 .086.214c0 .17-.136.307-.308.307a.303.303 0 0 1-.306-.307m3.11 1.596c-.2.081-.4.151-.591.16a1.25 1.25 0 0 1-.798-.254c-.274-.23-.47-.358-.551-.758a1.7 1.7 0 0 1 .015-.588c.07-.327-.007-.537-.238-.727-.188-.156-.426-.199-.689-.199a.6.6 0 0 1-.254-.078.253.253 0 0 1-.114-.358 1 1 0 0 1 .192-.21c.356-.202.767-.136 1.146.016.352.144.618.408 1.001.782.392.451.462.576.685.915.176.264.336.536.446.848.066.194-.02.353-.25.45"
    // Z.ai: подложка и три выреза буквы Z (из mask dsh-usage-hq).
    static let zaiSquare = "M24.51,28.51H5.49c-2.21,0-4-1.79-4-4V5.49c0-2.21,1.79-4,4-4h19.03c2.21,0,4,1.79,4,4v19.03 C28.51,26.72,26.72,28.51,24.51,28.51z"
    static let zaiCutouts = "M15.47,7.1l-1.3,1.85c-0.2,0.29-0.54,0.47-0.9,0.47h-7.1V7.09C6.16,7.1,15.47,7.1,15.47,7.1z M24.3,7.1 L13.14,22.91H5.7L16.86,7.1Z M14.53,22.91l1.31-1.86c0.2-0.29,0.54-0.47,0.9-0.47h7.09v2.33H14.53z"
}

/// Платформа Z: квадрат рисуется слоем, вырезы буквы Z стирают его через
/// destinationOut — прозрачность настоящая, без булевых операций над путями.
public struct ZShapeView: View {
    let square: String
    let cutouts: String
    let viewBox: CGFloat
    let color: Color

    public init(square: String, cutouts: String, viewBox: CGFloat, color: Color) {
        self.square = square
        self.cutouts = cutouts
        self.viewBox = viewBox
        self.color = color
    }

    public var body: some View {
        Canvas { context, canvasSize in
            let rect = CGRect(origin: .zero, size: canvasSize)
            // Один общий transform для квадрата и вырезов — координаты совпадают.
            let paths = SVGPathShape.parsedPaths(dList: [square, cutouts],
                                                 viewBox: viewBox, in: rect)
            guard paths.count == 2 else { return }
            context.drawLayer { layer in
                layer.fill(paths[0], with: .color(color))
                layer.blendMode = .destinationOut
                layer.fill(paths[1], with: .color(.black))
            }
        }
    }
}

/// Мини-парсер SVG path → SwiftUI Path (достаточно для логотипов DSH).
struct SVGPathShape: Shape {
    let d: String
    let viewBox: CGFloat

    func path(in rect: CGRect) -> Path {
        Self.parsedPath(d: d, viewBox: viewBox, in: rect)
    }

    static func parsedPath(d: String, viewBox: CGFloat, in rect: CGRect) -> Path {
        parsedPaths(dList: [d], viewBox: viewBox, in: rect).first ?? Path()
    }

    /// Все подпути в ЕДИНОЙ системе координат viewBox: масштаб и центрирование
    /// по объединённым границам — вырезы остаются совмещёнными с подложкой.
    static func parsedPaths(dList: [String], viewBox: CGFloat, in rect: CGRect) -> [Path] {
        let scale = min(rect.width / viewBox, rect.height / viewBox)
        var paths = dList.map { SVGPathParser.parse($0) }
        guard !paths.isEmpty else { return paths }
        var bounds = paths[0].boundingRect
        for subpath in paths.dropFirst() {
            bounds = bounds.union(subpath.boundingRect)
        }
        guard bounds.width > 0, bounds.height > 0 else { return paths }
        var transform = CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY)
            .scaledBy(x: scale, y: scale)
        transform.tx += (rect.width - bounds.width * scale) / 2
        transform.ty += (rect.height - bounds.height * scale) / 2
        return paths.map { $0.applying(transform) }
    }
}

enum SVGPathParser {
    static func parse(_ d: String) -> Path {
        var path = Path()
        var current = CGPoint.zero
        var start = CGPoint.zero
        var previousControl: CGPoint?
        var previousCommand: Character = " "

        var index = d.startIndex
        func skipSeparators() {
            while index < d.endIndex, ", \t\r\n".contains(d[index]) { index = d.index(after: index) }
        }
        func number() -> Double? {
            skipSeparators()
            let start = index
            if index < d.endIndex, "+-".contains(d[index]) { index = d.index(after: index) }
            var seenDot = false
            while index < d.endIndex {
                let char = d[index]
                if char.isNumber { index = d.index(after: index) }
                else if char == ".", !seenDot { seenDot = true; index = d.index(after: index) }
                else { break }
            }
            guard start < index, let value = Double(d[start..<index]) else { index = start; return nil }
            return value
        }
        func point() -> CGPoint? {
            guard let x = number(), let y = number() else { return nil }
            return CGPoint(x: x, y: y)
        }
        func isCommand(_ char: Character) -> Bool {
            "MmLlHhVvCcSsQqTtAaZz".contains(char)
        }

        while index < d.endIndex {
            skipSeparators()
            guard index < d.endIndex else { break }
            var command = d[index]
            if isCommand(command) {
                index = d.index(after: index)
            } else if "MmZz".contains(previousCommand) {
                // После M/m следующие пары координат трактуются как L/l (SVG).
                command = previousCommand == "m" ? "l" : "L"
            } else if "LlHhVvCcSsQqTtAa".contains(previousCommand) {
                // Неявное повторение команды: последующие наборы параметров
                // относятся к той же команде (стандарт SVG 1.1, путь OpenAI).
                command = previousCommand
            } else {
                break
            }
            let upper = command.uppercased().first!
            let relative = command != upper

            func absolute(_ point: CGPoint?) -> CGPoint? {
                guard let point else { return nil }
                return relative ? CGPoint(x: current.x + point.x, y: current.y + point.y) : point
            }

            switch upper {
            case "M":
                guard let next = absolute(point()) else { return path }
                path.move(to: next)
                current = next
                start = next
                previousControl = nil
            case "L":
                guard let next = absolute(point()) else { return path }
                path.addLine(to: next)
                current = next
                previousControl = nil
            case "H":
                guard let x = number() else { return path }
                let next = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: next)
                current = next
                previousControl = nil
            case "V":
                guard let y = number() else { return path }
                let next = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: next)
                current = next
                previousControl = nil
            case "C":
                guard let c1 = absolute(point()), let c2 = absolute(point()), let to = absolute(point()) else { return path }
                path.addCurve(to: to, control1: c1, control2: c2)
                previousControl = c2
                current = to
            case "S":
                guard let c2 = absolute(point()), let to = absolute(point()) else { return path }
                let reflected = relativeControl(current: current, previous: previousControl, previousCommand: previousCommand)
                path.addCurve(to: to, control1: reflected, control2: c2)
                previousControl = c2
                current = to
            case "Q":
                guard let control = absolute(point()), let to = absolute(point()) else { return path }
                path.addQuadCurve(to: to, control: control)
                previousControl = control
                current = to
            case "T":
                guard let to = absolute(point()) else { return path }
                let reflected = relativeControl(current: current, previous: previousControl, previousCommand: previousCommand)
                path.addQuadCurve(to: to, control: reflected)
                previousControl = reflected
                current = to
            case "A":
                guard let rx = number(), let ry = number(), let rotation = number(),
                      let largeArc = number(), let sweep = number(),
                      let to = absolute(point()) else { return path }
                appendArc(to: &path, from: current, to: to,
                          rx: max(abs(rx), 0.0001), ry: max(abs(ry), 0.0001),
                          xAxisRotation: rotation * .pi / 180,
                          largeArc: largeArc != 0, sweep: sweep != 0)
                current = to
                previousControl = nil
            case "Z":
                path.closeSubpath()
                current = start
                previousControl = nil
            default:
                return path
            }
            previousCommand = command
        }
        return path
    }

    /// Отражение контрольной точки для S/T относительно текущей точки.
    private static func relativeControl(current: CGPoint, previous: CGPoint?, previousCommand: Character) -> CGPoint {
        guard let previous, "CcSsQqTt".contains(previousCommand) else { return current }
        return CGPoint(x: 2 * current.x - previous.x, y: 2 * current.y - previous.y)
    }

    /// Дуга → кубические кривые (F.6.2 спецификации SVG 1.1).
    private static func appendArc(to path: inout Path, from: CGPoint, to: CGPoint,
                                  rx: Double, ry: Double, xAxisRotation: Double,
                                  largeArc: Bool, sweep: Bool) {
        let dx2 = (from.x - to.x) / 2
        let dy2 = (from.y - to.y) / 2
        let cos = Foundation.cos(xAxisRotation)
        let sin = Foundation.sin(xAxisRotation)
        let x1p = cos * dx2 + sin * dy2
        let y1p = -sin * dx2 + cos * dy2
        var rx = rx, ry = ry
        let lambda = x1p * x1p / (rx * rx) + y1p * y1p / (ry * ry)
        if lambda > 1 {
            let factor = Foundation.sqrt(lambda)
            rx *= factor
            ry *= factor
        }
        let sign: Double = largeArc != sweep ? 1 : -1
        let numerator = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let denominator = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        guard denominator != 0 else { return }
        let coefficient = sign * Foundation.sqrt(max(0, numerator / denominator))
        let cxp = coefficient * rx * y1p / ry
        let cyp = -coefficient * ry * x1p / rx
        let centerX = cos * cxp - sin * cyp + (from.x + to.x) / 2
        let centerY = sin * cxp + cos * cyp + (from.y + to.y) / 2

        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            let dot = ux * vx + uy * vy
            let length = Foundation.sqrt(ux * ux + uy * uy) * Foundation.sqrt(vx * vx + vy * vy)
            guard length != 0 else { return 0 }
            var angle = Foundation.acos(min(1, max(-1, dot / length)))
            if ux * vy - uy * vx < 0 { angle = -angle }
            return angle
        }

        let startAngle = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var deltaAngle = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && deltaAngle > 0 { deltaAngle -= 2 * .pi }
        if sweep && deltaAngle < 0 { deltaAngle += 2 * .pi }

        let segments = Int(ceil(abs(deltaAngle) / (.pi / 2)))
        let delta = deltaAngle / Double(max(segments, 1))
        let t = 4 / 3 * Foundation.tan(delta / 4)

        var theta = startAngle
        var point = from
        for _ in 0..<max(segments, 1) {
            let nextTheta = theta + delta
            let cos1 = Foundation.cos(theta), sin1 = Foundation.sin(theta)
            let cos2 = Foundation.cos(nextTheta), sin2 = Foundation.sin(nextTheta)
            let e1 = CGPoint(
                x: cos * rx * cos2 - sin * ry * sin2 + centerX,
                y: sin * rx * cos2 + cos * ry * sin2 + centerY)
            let d1 = CGPoint(
                x: t * (-cos * rx * sin1 - sin * ry * cos1),
                y: t * (-sin * rx * sin1 + cos * ry * cos1))
            let d2 = CGPoint(
                x: t * (cos * rx * sin2 + sin * ry * cos2),
                y: t * (sin * rx * sin2 - cos * ry * cos2))
            path.addCurve(to: e1, control1: CGPoint(x: point.x + d1.x, y: point.y + d1.y),
                          control2: CGPoint(x: e1.x + d2.x, y: e1.y + d2.y))
            point = e1
            theta = nextTheta
        }
    }
}

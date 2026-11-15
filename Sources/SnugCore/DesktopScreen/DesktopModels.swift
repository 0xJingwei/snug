// 桌面屏尺寸：电脑控制端连上多显示器 Mac 时，提供一块 2 倍 HiDPI 横向虚拟屏。
// macOS 对虚拟屏开放 2 倍模式的门槛是逻辑宽 ≥ 540 且高 ≥ 800 点；横向桌面屏统一约束在 800…2560 × 800…1600 点
import CoreGraphics
import Foundation

/// 桌面屏的逻辑分辨率（点，2 倍模式下对应双倍物理像素，横屏：宽不小于高）
public struct DesktopScreen: Codable, Hashable, Sendable {
    public static let widthRange = 800...2560
    public static let heightRange = 800...1600

    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var size: CGSize { CGSize(width: width, height: height) }

    /// 满足横屏且落在 2 倍 HiDPI 可用范围内
    public var isValid: Bool {
        Self.widthRange.contains(width) && Self.heightRange.contains(height) && width >= height
    }

    /// 自定义尺寸：竖着填的自动转成横屏；填了 2 倍物理像素（如 3024×1964、3840×2160）自动折半成逻辑点
    public static func custom(_ a: Int?, _ b: Int?) -> DesktopScreen? {
        guard let a, let b, a > 0, b > 0 else { return nil }
        var w = max(a, b)
        var h = min(a, b)
        if w > widthRange.upperBound || h > heightRange.upperBound {
            w /= 2
            h /= 2
        }
        let screen = DesktopScreen(width: w, height: h)
        return screen.isValid ? screen : nil
    }
}

/// 常见笔记本与桌面横屏预设
public struct DesktopPreset: Equatable, Sendable, Identifiable {
    public let name: String
    public let screen: DesktopScreen

    public var id: String { name }

    public static let all: [DesktopPreset] = [
        DesktopPreset(name: "MacBook Air 13\"", screen: DesktopScreen(width: 1470, height: 956)),
        DesktopPreset(name: "MacBook Pro 14\"", screen: DesktopScreen(width: 1512, height: 982)),
        DesktopPreset(name: "MacBook Air 15\"", screen: DesktopScreen(width: 1710, height: 1107)),
        DesktopPreset(name: "MacBook Pro 16\"", screen: DesktopScreen(width: 1728, height: 1117)),
        DesktopPreset(name: "1440 × 900 (16:10)", screen: DesktopScreen(width: 1440, height: 900)),
        DesktopPreset(name: "1920 × 1080 (16:9)", screen: DesktopScreen(width: 1920, height: 1080)),
        DesktopPreset(name: "2560 × 1440 (16:9)", screen: DesktopScreen(width: 2560, height: 1440)),
        DesktopPreset(name: "2560 × 1600 (16:10)", screen: DesktopScreen(width: 2560, height: 1600)),
    ]

    public static func named(_ name: String) -> DesktopPreset? {
        all.first { $0.name == name }
    }
}

/// 用户选定的桌面屏尺寸：预设名或自定义逻辑尺寸
public struct DesktopChoice: Codable, Equatable, Sendable {
    /// 预设名（DesktopPreset.id）；自定义为 nil
    public var preset: String?
    public var screen: DesktopScreen

    public init(preset: String?, screen: DesktopScreen) {
        self.preset = preset
        self.screen = screen
    }

    public init(_ preset: DesktopPreset) {
        self.init(preset: preset.id, screen: preset.screen)
    }

    public static let standard = DesktopChoice(preset: "MacBook Pro 14\"", screen: DesktopScreen(width: 1512, height: 982))

    /// 预设表若调过数值则跟进；预设被改名或属于自定义则保留原值
    public func resolved() -> DesktopChoice {
        guard let id = preset, let found = DesktopPreset.named(id) else { return self }
        return DesktopChoice(found)
    }
}

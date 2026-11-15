// 屏幕查找与坐标换算。AppKit（NSScreen、窗口）用左下原点，辅助功能和 CGEvent 用主屏左上原点
import AppKit
import SnugCore

@MainActor
public enum Screens {
    public static func displayID(of screen: NSScreen) -> DisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value
    }

    public static func screen(for id: DisplayID) -> NSScreen? {
        NSScreen.screens.first { displayID(of: $0) == id }
    }

    /// 在「显示器」设置里的名字；找不到就用编号
    public static func name(of id: DisplayID) -> String {
        screen(for: id)?.localizedName ?? "显示器 #\(id)"
    }

    /// 主屏：菜单栏所在、原点为 0,0 的那块
    public static var primary: NSScreen? { NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first }

    /// AppKit 坐标 → 辅助功能坐标
    public static func axRect(fromAppKit rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: (primary?.frame.height ?? 0) - rect.maxY, width: rect.width, height: rect.height)
    }
}

// 桌面屏聚拢窗口的还原账本：挪动前先把原位写盘，断开还原成功或窗口已关闭才逐条销账。
// Snug 崩溃时系统自动撤掉桌面屏、把窗口散落到主屏，下次启动按这份账本逐一归位到原来的各个物理显示器
import CoreGraphics
import Foundation

public struct DesktopWindowRecord: Codable, Equatable, Sendable {
    public var window: WindowKey
    public var app: String
    public var label: String
    /// 原位（辅助功能坐标：左上原点）
    public var original: CGRect
    public var wasFullScreen: Bool

    public init(window: WindowKey, app: String, label: String, original: CGRect, wasFullScreen: Bool = false) {
        self.window = window
        self.app = app
        self.label = label
        self.original = original
        self.wasFullScreen = wasFullScreen
    }
}

public struct DesktopRecord: Codable, Equatable, Sendable {
    public var windows: [DesktopWindowRecord]

    public init(windows: [DesktopWindowRecord] = []) {
        self.windows = windows
    }
}

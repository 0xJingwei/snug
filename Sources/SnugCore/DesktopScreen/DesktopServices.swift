// DesktopDesk 要用到的虚拟屏能力。窗口控制复用 WindowControl
import CoreGraphics
import Foundation

@MainActor
public protocol DesktopDisplays: AnyObject {
    /// 按指定逻辑尺寸建一块 2 倍 HiDPI 横向桌面屏并等待上线
    func create(_ screen: DesktopScreen) async throws -> DisplayID
    /// 在线切换桌面屏的目标尺寸（不掉线、编号不变）
    func reshape(_ id: DisplayID, to screen: DesktopScreen) async -> Bool
    /// 这块桌面屏当前登记的目标尺寸；不是本进程建的返回 nil
    func screen(_ id: DisplayID) -> DesktopScreen?
    /// 此刻实际生效的 2 倍模式尺寸；不是 2 倍或屏不在了返回 nil
    func size(_ id: DisplayID) -> DesktopScreen?
    /// 切回指定 2 倍模式尺寸
    func setSize(_ id: DisplayID, _ screen: DesktopScreen) async
    /// 释放并等待下线
    func retire(_ id: DisplayID) async
    /// 整块屏的范围（辅助功能坐标，左上原点）
    func bounds(_ id: DisplayID) -> CGRect?
    /// 扣掉菜单栏与程序坞后的可放窗口区域（辅助功能坐标，左上原点）
    func windowArea(_ id: DisplayID) -> CGRect?
    /// 包含该点的物理屏可放窗口区域（排除虚拟屏）；找不到时退回主屏可放区域
    func sourceArea(containing point: CGPoint, excluding: Set<DisplayID>) -> CGRect?
    /// 主屏的可放窗口区域
    func mainArea() -> CGRect?
}

public enum DesktopScreenError: Error, CustomStringConvertible {
    case createFailed
    case neverOnline

    public var description: String {
        switch self {
        case .createFailed: "桌面屏 CGVirtualDisplay 建不出来，备用身份也都试过了"
        case .neverOnline: "桌面屏建好了但一直不上线，备用身份也都试过了"
        }
    }
}

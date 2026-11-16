// 一块屏的显示模式，和帮手进程要切到哪个模式。
// 加屏、撤屏前记下别的屏的模式，换完把被 macOS 拨动的设回去（见 PhoneDesk 的 Surroundings）
import Foundation

public struct ScreenMode: Equatable, Sendable, CustomStringConvertible {
    /// 系统给这一档的编号（CGDisplayModeGetIODisplayModeID），只在这块屏里有意义；虚拟屏可能是 0
    public var ioModeID: Int32
    /// 点数
    public var width: Int
    public var height: Int
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var refreshRate: Double

    public init(ioModeID: Int32, width: Int, height: Int, pixelWidth: Int, pixelHeight: Int, refreshRate: Double) {
        self.ioModeID = ioModeID
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshRate = refreshRate
    }

    public var description: String {
        let scale = pixelWidth == width ? " " : pixelWidth == 2 * width ? "（2 倍）" : "（\(pixelWidth)x\(pixelHeight) 像素）"
        let hz = refreshRate.rounded() == refreshRate ? String(Int(refreshRate)) : String(format: "%.2f", refreshRate)
        return "\(width)x\(height)\(scale)\(hz)Hz"
    }
}

/// 帮手进程（Snug --set-mode / --restore-mode）要把屏切到哪个模式
public enum ModeTarget: Equatable, Sendable, CustomStringConvertible {
    /// 手机屏换档：width × height（点）的 2 倍模式，只对本次登录生效
    case hiDPI(width: Int, height: Int)
    /// 别的屏：原样设回这个模式，连永久配置一起（加屏、撤屏时系统把套用来的旧模式也写进了永久配置）
    case exact(ScreenMode)

    /// 交给帮手的命令行参数，LaunchMode 按同一套解析回来
    public func arguments(display: DisplayID) -> [String] {
        switch self {
        case .hiDPI(let width, let height):
            ["--set-mode", "\(display)", "\(width)", "\(height)"]
        case .exact(let m):
            ["--restore-mode", "\(display)", "\(m.ioModeID)", "\(m.width)", "\(m.height)", "\(m.pixelWidth)", "\(m.pixelHeight)", "\(m.refreshRate)"]
        }
    }

    public var description: String {
        switch self {
        case .hiDPI(let width, let height): "2 倍 \(width)x\(height)"
        case .exact(let mode): "\(mode)（模式 \(mode.ioModeID)）"
        }
    }
}

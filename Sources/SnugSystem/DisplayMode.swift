// 显示模式：读此刻是哪一档，以及帮手进程里真正去切。
// 主程序不亲自切模式：亲自切过模式的进程，这块虚拟屏释放后要拖 40 秒以上才下线（两次实测）；
// 交给短命的帮手进程（Snug --set-mode）切完就退出，释放照样 0.1 秒下线
import CoreGraphics
import SnugCore

public enum DisplayMode {
    public enum Outcome: Equatable, CustomStringConvertible {
        case switched
        /// 这块屏没有这一档的 2 倍模式
        case unavailable
        case failed(CGError)

        public var description: String {
            switch self {
            case .switched: "已切换"
            case .unavailable: "没有这一档的 2 倍模式"
            case .failed(let err): "切换失败（CGError=\(err.rawValue)）"
            }
        }
    }

    /// 此刻 2 倍模式的宽度（点）；不是 2 倍、或屏不在了返回 nil
    public static func hiDPIWidth(_ id: DisplayID) -> Int? {
        guard let mode = CGDisplayCopyDisplayMode(id), mode.pixelWidth == 2 * mode.width else { return nil }
        return mode.width
    }

    /// 此刻 2 倍模式的逻辑宽高（点）；不是 2 倍、或屏不在了返回 nil
    public static func hiDPISize(_ id: DisplayID) -> DesktopScreen? {
        guard let mode = CGDisplayCopyDisplayMode(id),
              mode.pixelWidth == 2 * mode.width, mode.pixelHeight == 2 * mode.height else { return nil }
        return DesktopScreen(width: mode.width, height: mode.height)
    }

    public static func describe(_ id: DisplayID) -> String {
        guard let m = CGDisplayCopyDisplayMode(id) else { return "无模式" }
        return "\(m.width)x\(m.height)pt/\(m.pixelWidth)x\(m.pixelHeight)px"
    }

    /// 系统列出了 width×height 的 2 倍模式没有（换了模式表要等一会儿才列出来）
    public static func hasHiDPI(_ id: DisplayID, width: Int, height: Int) -> Bool {
        hiDPIMode(id, width: width, height: height) != nil
    }

    private static func hiDPIMode(_ id: DisplayID, width: Int, height: Int) -> CGDisplayMode? {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        let modes = (CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode]) ?? []
        return modes.first { $0.width == width && $0.height == height && $0.pixelWidth == 2 * width }
    }

    /// 帮手进程里调用：切到 2 倍的 width×height（点）。只对本次登录生效
    public static func switchToHiDPI(_ id: DisplayID, width: Int, height: Int) -> Outcome {
        guard let mode = hiDPIMode(id, width: width, height: height) else { return .unavailable }
        var config: CGDisplayConfigRef?
        let begin = CGBeginDisplayConfiguration(&config)
        guard begin == .success else { return .failed(begin) }
        let staged = CGConfigureDisplayWithDisplayMode(config, id, mode, nil)
        guard staged == .success else {
            CGCancelDisplayConfiguration(config)
            return .failed(staged)
        }
        let done = CGCompleteDisplayConfiguration(config, .forSession)
        if done != .success { CGCancelDisplayConfiguration(config) }
        return done == .success ? .switched : .failed(done)
    }

    /// 帮手进程里调用：把实体显示器精确恢复到原来的逻辑尺寸、像素尺寸与刷新率
    public static func switchToExactMode(
        _ id: DisplayID,
        width: Int,
        height: Int,
        pixelWidth: Int,
        pixelHeight: Int,
        refreshRate: Int
    ) -> Outcome {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        let modes = (CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode]) ?? []
        let candidates = modes.filter {
            $0.width == width && $0.height == height
                && $0.pixelWidth == pixelWidth && $0.pixelHeight == pixelHeight
        }
        let chosen = candidates.first { Int($0.refreshRate.rounded()) == refreshRate } ?? candidates.first
        guard let mode = chosen else { return .unavailable }
        var config: CGDisplayConfigRef?
        let begin = CGBeginDisplayConfiguration(&config)
        guard begin == .success else { return .failed(begin) }
        let staged = CGConfigureDisplayWithDisplayMode(config, id, mode, nil)
        guard staged == .success else {
            CGCancelDisplayConfiguration(config)
            return .failed(staged)
        }
        let done = CGCompleteDisplayConfiguration(config, .forSession)
        if done != .success { CGCancelDisplayConfiguration(config) }
        return done == .success ? .switched : .failed(done)
    }
}

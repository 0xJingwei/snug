// 桌面屏的身份与物理参数：独立于手机屏的产品号和序列号池，避免两块屏同时在线或复用 ICC 时串扰
import Foundation

public enum DesktopScreenSpec {
    /// 在「显示器」设置和 UU远程 的屏幕列表里看到的名字
    public static let name = "Snug 桌面屏"
    /// 与手机屏同属 'SN' 厂商，但用独立 productID 区分
    public static let vendorID: UInt32 = PhoneScreenSpec.vendorID
    public static let productID: UInt32 = 0x00D0
    /// 建好不到这么久就释放会让 WindowServer 卡死
    public static let minimumLifetime: TimeInterval = 2.5

    /// 像素上限框住 2560×1600 的 2 倍 HiDPI（5120×3200）
    public static let maxPixels = (width: 5120.0, height: 3200.0)
    /// 物理尺寸按像素上限、约 220ppi 折算，确保首次建屏就能顺利上线
    public static let millimeters = (width: maxPixels.width / 220 * 25.4, height: maxPixels.height / 220 * 25.4)

    /// 固定主身份 + 两个备用身份，避免每次生成新的 ColorSync ICC 文件
    public static let serials: [UInt32] = [300_000_108, 300_000_118, 300_000_128]
}

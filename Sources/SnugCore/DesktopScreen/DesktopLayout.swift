// 桌面屏窗口排布：大屏（4K、带鱼屏、竖置副屏）上的窗口聚拢到笔记本尺寸的桌面屏时，
// 超出桌面屏可用区域的宽高夹紧到可用区域内，比桌面屏小的窗口保持原尺寸并按原屏相对位置落位
import CoreGraphics
import Foundation

public enum DesktopLayout {
    /// 把原屏（sourceArea）上的窗口框换算成桌面屏可用区（targetArea）内的框
    public static func fittedFrame(for frame: CGRect, from sourceArea: CGRect?, into targetArea: CGRect) -> CGRect {
        let width = min(frame.width, targetArea.width)
        let height = min(frame.height, targetArea.height)
        let slackX = max(0, targetArea.width - width)
        let slackY = max(0, targetArea.height - height)

        let rx: CGFloat
        let ry: CGFloat
        if let src = sourceArea, src.width > 0, src.height > 0 {
            rx = src.width > frame.width ? ((frame.minX - src.minX) / (src.width - frame.width)).clamped(to: 0...1) : 0.5
            ry = src.height > frame.height ? ((frame.minY - src.minY) / (src.height - frame.height)).clamped(to: 0...1) : 0.5
        } else {
            rx = 0.5
            ry = 0.5
        }

        let x = (targetArea.minX + slackX * rx).rounded().clamped(to: targetArea.minX...(targetArea.maxX - width))
        let y = (targetArea.minY + slackY * ry).rounded().clamped(to: targetArea.minY...(targetArea.maxY - height))
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

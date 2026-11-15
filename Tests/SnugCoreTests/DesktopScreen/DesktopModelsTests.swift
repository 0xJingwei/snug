import CoreGraphics
import Foundation
import Testing
@testable import SnugCore

@Suite("桌面屏规格与尺寸 DesktopScreen")
struct DesktopModelsTests {
    @Test("物理尺寸按 5120×3200 像素上限与 220ppi 折算；产品号与序列号与手机屏严格隔离")
    func spec() {
        let mm = DesktopScreenSpec.millimeters
        #expect(abs(mm.width - 5120.0 / 220 * 25.4) < 0.001)
        #expect(abs(mm.height - 3200.0 / 220 * 25.4) < 0.001)
        #expect(DesktopScreenSpec.productID != PhoneScreenSpec.productID)
        #expect(Set(DesktopScreenSpec.serials).isDisjoint(with: PhoneScreenSpec.serials))
        #expect(DesktopScreenSpec.serials.count == 3)
    }

    @Test("全部内置预设均满足横屏且在 macOS 2 倍 HiDPI 可用范围内；默认预设在预设表中")
    func presets() {
        #expect(!DesktopPreset.all.isEmpty)
        for preset in DesktopPreset.all {
            #expect(preset.screen.isValid, "\(preset.name)")
        }
        #expect(DesktopPreset.named(DesktopChoice.standard.preset ?? "")?.screen == DesktopChoice.standard.screen)
        #expect(DesktopChoice.standard.resolved() == .standard)
    }

    @Test("自定义尺寸：竖向输入自动转横向；输入 2 倍物理像素自动折半为逻辑点；过小或超限拒收")
    func customScreen() {
        #expect(DesktopScreen.custom(1920, 1080) == DesktopScreen(width: 1920, height: 1080))
        #expect(DesktopScreen.custom(1080, 1920) == DesktopScreen(width: 1920, height: 1080))
        // 输入 Retina 物理像素（MacBook Pro 14" 3024×1964、4K 3840×2160）自动折成逻辑点
        #expect(DesktopScreen.custom(3024, 1964) == DesktopScreen(width: 1512, height: 982))
        #expect(DesktopScreen.custom(3840, 2160) == DesktopScreen(width: 1920, height: 1080))
        // 低于 2 倍门槛（高 < 800）或超大离谱的拒收
        #expect(DesktopScreen.custom(1280, 720) == nil)
        #expect(DesktopScreen.custom(640, 480) == nil)
        #expect(DesktopScreen.custom(8000, 5000) == nil)
        #expect(DesktopScreen.custom(nil, 1080) == nil)
        #expect(DesktopScreen.custom(0, 1080) == nil)
    }
}

@Suite("多屏窗口聚拢排布 DesktopLayout")
struct DesktopLayoutTests {
    private let target = CGRect(x: 6000, y: 25, width: 1512, height: 957)

    @Test("2K/4K 横屏与竖置副屏上的超大窗口夹紧到桌面屏可用区域内，绝不越界")
    func clampsOversizedWindows() {
        // 2560×1440 外接屏上铺满的大窗口
        let big = DesktopLayout.fittedFrame(
            for: CGRect(x: 1728, y: 25, width: 2560, height: 1415),
            from: CGRect(x: 1728, y: 25, width: 2560, height: 1415),
            into: target)
        #expect(big == target)

        // 负坐标竖置副屏（-1980,-1413 1440×2530）上的高窗口：宽度保留 1440，高度夹紧到 957
        let portraitSource = CGRect(x: -1980, y: -1413, width: 1440, height: 2530)
        let tall = DesktopLayout.fittedFrame(
            for: CGRect(x: -1980, y: -1413, width: 1440, height: 2400),
            from: portraitSource,
            into: target)
        #expect(tall.width == 1440)
        #expect(tall.height == 957)
        #expect(target.contains(tall))
    }

    @Test("比桌面屏小的窗口保持原尺寸，并保留在原显示器上的左右相对方位")
    func preservesSizeAndRelativePosition() {
        let external = CGRect(x: 1728, y: 25, width: 2560, height: 1415)
        let leftWin = DesktopLayout.fittedFrame(
            for: CGRect(x: 1728, y: 25, width: 900, height: 600),
            from: external,
            into: target)
        #expect(leftWin == CGRect(x: 6000, y: 25, width: 900, height: 600))

        let rightWin = DesktopLayout.fittedFrame(
            for: CGRect(x: 1728 + 2560 - 900, y: 25 + 1415 - 600, width: 900, height: 600),
            from: external,
            into: target)
        #expect(rightWin == CGRect(x: 6000 + 1512 - 900, y: 25 + 957 - 600, width: 900, height: 600))
    }
}

import Foundation
import Testing
@testable import SnugCore

@Suite("启动参数 LaunchMode")
struct LaunchModeTests {
    @Test("没有参数：正常启动")
    func plain() throws {
        #expect(try LaunchMode.parse([]) == .app)
    }

    @Test("系统或 Cocoa 塞进来的单横线参数（-psn_…、-AppleLanguages …）一律忽略")
    func ignoresCocoaArguments() throws {
        #expect(try LaunchMode.parse(["-psn_0_12345"]) == .app)
        #expect(try LaunchMode.parse(["-AppleLanguages", "(zh-Hans)"]) == .app)
    }

    @Test("每种界面都有 --render-<界面> <目录>")
    func renders() throws {
        let out = URL(fileURLWithPath: "/tmp/out")
        for target in RenderTarget.allCases {
            #expect(try LaunchMode.parse(["--render-\(target.rawValue)", "/tmp/out"]) == .render(target, output: out))
        }
    }

    @Test("--set-mode <屏幕编号> <宽> <高>")
    func setMode() throws {
        #expect(try LaunchMode.parse(["--set-mode", "14", "740", "1302"]) == .setMode(display: 14, to: .hiDPI(width: 740, height: 1302)))
    }

    @Test("--restore-mode <屏幕编号> <模式编号> <宽> <高> <像素宽> <像素高> <刷新率>：模式编号可以是 0（虚拟屏），刷新率可以带小数")
    func restoreMode() throws {
        #expect(try LaunchMode.parse(["--restore-mode", "3", "13", "2560", "1440", "2560", "1440", "59.94"])
                == .setMode(display: 3, to: .exact(ScreenMode(ioModeID: 13, width: 2560, height: 1440, pixelWidth: 2560, pixelHeight: 1440, refreshRate: 59.94))))
        #expect(try LaunchMode.parse(["--restore-mode", "3", "0", "540", "1170", "1080", "2340", "60"])
                == .setMode(display: 3, to: .exact(ScreenMode(ioModeID: 0, width: 540, height: 1170, pixelWidth: 1080, pixelHeight: 2340, refreshRate: 60))))
        #expect(throws: LaunchModeError.invalidNumber("--restore-mode", "1.5")) {
            try LaunchMode.parse(["--restore-mode", "3", "1.5", "2560", "1440", "2560", "1440", "60"])
        }
        #expect(throws: LaunchModeError.invalidNumber("--restore-mode", "abc")) {
            try LaunchMode.parse(["--restore-mode", "3", "13", "2560", "1440", "2560", "1440", "abc"])
        }
        #expect(throws: LaunchModeError.missingValue("--restore-mode")) { try LaunchMode.parse(["--restore-mode", "3", "13", "2560"]) }
    }

    @Test("帮手把模式原样传下去：设回模式的参数由同一个模式拼出来，读回来不走样")
    func restoreModeRoundTrip() throws {
        let mode = ScreenMode(ioModeID: 7, width: 1512, height: 982, pixelWidth: 3024, pixelHeight: 1964, refreshRate: 59.94005994005994)
        #expect(try LaunchMode.parse(ModeTarget.exact(mode).arguments(display: 9)) == .setMode(display: 9, to: .exact(mode)))
        #expect(try LaunchMode.parse(ModeTarget.hiDPI(width: 540, height: 1170).arguments(display: 9)) == .setMode(display: 9, to: .hiDPI(width: 540, height: 1170)))
    }

    @Test("--dump-uu、--preview-phone")
    func flags() throws {
        #expect(try LaunchMode.parse(["--dump-uu"]) == .dumpUU)
        #expect(try LaunchMode.parse(["--preview-phone"]) == .previewPhone)
    }

    @Test("缺参数值、数字写错、两个模式一起：报错而不是悄悄按正常模式启动")
    func errors() {
        #expect(throws: LaunchModeError.missingValue("--render-settings")) { try LaunchMode.parse(["--render-settings"]) }
        #expect(throws: LaunchModeError.missingValue("--set-mode")) { try LaunchMode.parse(["--set-mode", "14"]) }
        #expect(throws: LaunchModeError.missingValue("--set-mode")) { try LaunchMode.parse(["--set-mode", "14", "540"]) }
        #expect(throws: LaunchModeError.invalidNumber("--set-mode", "abc")) { try LaunchMode.parse(["--set-mode", "abc", "540", "950"]) }
        #expect(throws: LaunchModeError.invalidNumber("--set-mode", "0")) { try LaunchMode.parse(["--set-mode", "14", "0", "950"]) }
        #expect(throws: LaunchModeError.conflicting("--dump-uu", "--render-about")) {
            try LaunchMode.parse(["--dump-uu", "--render-about", "/tmp/out"])
        }
    }

    @Test("已删掉的旧参数和未知的双横线参数：报错")
    func removedFlags() {
        for flag in ["--watchdog", "--simulate", "--stress", "--render-tour", "--render-permissions", "--tour"] {
            #expect(throws: LaunchModeError.unknownFlag(flag)) { try LaunchMode.parse([flag, "x"]) }
        }
    }
}

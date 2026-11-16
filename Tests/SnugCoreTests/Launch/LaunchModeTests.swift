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

    @Test("--set-mode 与 --restore-mode")
    func setMode() throws {
        #expect(try LaunchMode.parse(["--set-mode", "14", "740", "1302"]) == .setMode(display: 14, width: 740, height: 1302))
        #expect(
            try LaunchMode.parse(["--restore-mode", "3", "1920", "1200", "3840", "2400", "60"])
                == .restoreMode(display: 3, width: 1920, height: 1200, pixelWidth: 3840, pixelHeight: 2400, refreshRate: 60)
        )
    }

    @Test("--dump-uu、--preview-phone、--preview-desktop")
    func flags() throws {
        #expect(try LaunchMode.parse(["--dump-uu"]) == .dumpUU)
        #expect(try LaunchMode.parse(["--preview-phone"]) == .previewPhone)
        #expect(try LaunchMode.parse(["--preview-desktop"]) == .previewDesktop)
        #expect(throws: LaunchModeError.conflicting("--preview-phone", "--preview-desktop")) {
            try LaunchMode.parse(["--preview-phone", "--preview-desktop"])
        }
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

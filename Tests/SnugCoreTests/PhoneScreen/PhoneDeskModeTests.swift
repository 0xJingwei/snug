import CoreGraphics
import Foundation
import Testing
@testable import SnugCore

// 加屏、撤屏不动别的屏的模式（issue #13）。macOS 按「这组屏幕」各记一份模式，屏幕组合一变就把别的屏拨回它给新组合记的那份：
// UU 远程时把主屏临时切到 30Hz，系统给「没有手机屏的那组」记下 30Hz；撤手机屏时组合变回去，主屏就被拨回 30Hz

private let redmi60 = ScreenMode(ioModeID: 12, width: 2560, height: 1440, pixelWidth: 2560, pixelHeight: 1440, refreshRate: 60)
private let redmi30 = ScreenMode(ioModeID: 13, width: 2560, height: 1440, pixelWidth: 2560, pixelHeight: 1440, refreshRate: 30)
private let hp = ScreenMode(ioModeID: 5, width: 1080, height: 1920, pixelWidth: 1080, pixelHeight: 1920, refreshRate: 60)
private let builtIn = ScreenMode(ioModeID: 54, width: 1512, height: 982, pixelWidth: 3024, pixelHeight: 1964, refreshRate: 120)

@Suite("加屏、撤屏不动别的屏 PhoneDesk")
@MainActor
struct PhoneDeskModeTests {
    @Test("撤屏时 macOS 把别的屏拨回它给这组屏幕记的模式（远程时临时切的 30Hz）：撤完设回撤屏前的样子，没被拨动的不碰")
    func retireKeepsOtherModes() async throws {
        let rig = try Rig()
        rig.displays.others = [1: redmi60, 3: hp]
        await rig.ready()
        rig.displays.onRetire = { [unowned displays = rig.displays] in displays.others[1] = redmi30 }
        rig.desk.setWanted(false)
        await rig.desk.idle()
        #expect(rig.journal.all == ["snapshot", "retire 101", "restore", "mode 1 \(redmi60)"])
        #expect(rig.displays.others == [1: redmi60, 3: hp])
    }

    @Test("加屏时也一样：别的屏被拨回这组屏幕上次记的模式，加好后设回加屏前的样子（远程时 UU 正用着的 30Hz 也照旧）")
    func createKeepsOtherModes() async throws {
        let rig = try Rig()
        rig.displays.others = [1: redmi30, 3: hp]
        rig.displays.onCreate = { [unowned displays = rig.displays] in displays.others[1] = redmi60 }
        rig.desk.setWanted(true)
        await rig.desk.idle()
        #expect(rig.journal.all == ["snapshot", "create", "restore", "mode 1 \(redmi30)"])
        #expect(rig.displays.others == [1: redmi30, 3: hp])
    }

    @Test("这期间拔掉的屏、新接上的屏都不碰；都没变就什么都不做")
    func onlyScreensPresentThroughout() async throws {
        let rig = try Rig()
        rig.displays.others = [1: redmi60, 3: hp]
        await rig.ready()
        rig.displays.onRetire = { [unowned displays = rig.displays] in
            displays.others[3] = nil
            displays.others[4] = builtIn
        }
        rig.desk.setWanted(false)
        await rig.desk.idle()
        #expect(!rig.journal.all.contains { $0.hasPrefix("mode") })

        let calm = try Rig()
        calm.displays.others = [1: redmi60]
        calm.desk.setWanted(true)
        await calm.desk.idle()
        calm.desk.setWanted(false)
        await calm.desk.idle()
        #expect(!calm.journal.all.contains { $0.hasPrefix("mode") })
    }

    @Test("设不回去（帮手失败）只记日志，照样撤完屏")
    func modeFailureDoesNotBlock() async throws {
        let rig = try Rig()
        rig.displays.others = [1: redmi60]
        rig.displays.modeFails = true
        await rig.ready()
        rig.displays.onRetire = { [unowned displays = rig.displays] in displays.others[1] = redmi30 }
        rig.desk.setWanted(false)
        await rig.desk.idle()
        #expect(rig.journal.all.contains("mode 1 \(redmi60)"))
        #expect(rig.desk.state.screen == .off)
    }

    @Test("模式在日志里写成点数、几倍、刷新率")
    func describesMode() {
        #expect("\(redmi30)" == "2560x1440 30Hz")
        #expect("\(builtIn)" == "1512x982（2 倍）120Hz")
        #expect("\(ScreenMode(ioModeID: 1, width: 1920, height: 1080, pixelWidth: 1920, pixelHeight: 1080, refreshRate: 59.94))" == "1920x1080 59.94Hz")
    }
}

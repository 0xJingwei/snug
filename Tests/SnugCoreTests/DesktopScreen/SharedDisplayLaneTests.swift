import CoreGraphics
import Foundation
import Testing
@testable import SnugCore

@Suite("手机与桌面共享显示事务")
@MainActor
struct SharedDisplayLaneTests {
    @Test("同时请求两种屏：快照、建撤屏、归位串行，竖屏负坐标不被临时快照覆盖")
    func mixedDisplaysPreservePortraitWindows() async throws {
        let tmp = try TempDir()
        let paths = SnugPaths(dataDirectory: tmp.url, logFile: tmp.url.appendingPathComponent("Snug.log"))
        let journal = Journal()
        let windows = FakeWindows(journal: journal)
        let original = CGRect(x: -1440, y: -1413, width: 1440, height: 2530)
        windows.add(finder.key, frame: original, info: finder)
        let timeline = ManualTimeline()
        let phones = FakeDisplays(journal: journal)
        let desktops = FakeDesktopDisplays(journal: journal)
        let lane = SerialLane()
        let phone = PhoneDesk(displays: phones, windows: windows,
                              apps: FakeApps(journal: journal, windows: windows, timeline: timeline),
                              timeline: timeline, paths: paths, lane: lane)
        let desktop = DesktopDesk(displays: desktops, windows: windows, timeline: timeline, paths: paths, lane: lane)
        phones.onCreate = { windows.setFrame(finder.key, original.offsetBy(dx: -540, dy: 0)) }
        desktops.onCreate = { windows.setFrame(finder.key, original.offsetBy(dx: -1080, dy: 0)) }
        phones.onRetire = { windows.setFrame(finder.key, original.offsetBy(dx: 540, dy: 0)) }
        desktops.onRetire = { windows.setFrame(finder.key, original.offsetBy(dx: 1080, dy: 0)) }
        phone.setWanted(true)
        desktop.setWanted(true)
        await lane.drain()
        #expect(windows.window(finder.key)?.frame == original)
        #expect(Array(journal.all.prefix(6)) == ["snapshot", "create", "restore", "snapshot", "desktop.create 1512x982", "restore"])
        phone.setWanted(false)
        desktop.setWanted(false)
        await lane.drain()
        #expect(windows.window(finder.key)?.frame == original)
        #expect(phone.state.screen == .off)
        #expect(desktop.state.screen == .off)
    }
}

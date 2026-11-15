import CoreGraphics
import Foundation
import Testing
@testable import SnugCore

@MainActor
final class FakeDesktopDisplays: DesktopDisplays {
    nonisolated static let origin = CGPoint(x: 6000, y: 0)
    nonisolated static let menuBar: CGFloat = 25
    nonisolated static let main = CGRect(x: 0, y: 25, width: 1728, height: 1092)

    /// 模拟 4 块物理屏：#1 内建屏 + #2/#3 横向 2K 外接屏 + #5 负坐标竖置外接屏
    let physicalScreens: [DisplayID: CGRect] = [
        1: CGRect(x: 0, y: 25, width: 1728, height: 1092),
        2: CGRect(x: 1728, y: 25, width: 2560, height: 1415),
        3: CGRect(x: 4288, y: 25, width: 2560, height: 1415),
        5: CGRect(x: -1440, y: -1413, width: 1440, height: 2530),
    ]
    var extraBounds: [DisplayID: CGRect] = [:]

    let journal: Journal
    var nextID: DisplayID = 200
    var failuresLeft = 0
    var reshapeFails = false
    var setSizeFails = false
    var onCreate: (() -> Void)?
    var onRetire: (() -> Void)?
    var clock: (() -> TimeInterval)?
    private(set) var createdAt: [DisplayID: TimeInterval] = [:]
    private(set) var retiredAt: [DisplayID: TimeInterval] = [:]
    private(set) var registered: [DisplayID: DesktopScreen] = [:]
    var activeSizes: [DisplayID: DesktopScreen] = [:]

    init(journal: Journal) { self.journal = journal }

    func create(_ screen: DesktopScreen) async throws -> DisplayID {
        journal.add("desktop.create \(screen.width)x\(screen.height)")
        if failuresLeft > 0 {
            failuresLeft -= 1
            throw DesktopScreenError.neverOnline
        }
        nextID += 1
        createdAt[nextID] = clock?()
        registered[nextID] = screen
        activeSizes[nextID] = screen
        onCreate?()
        return nextID
    }

    func retire(_ id: DisplayID) async {
        journal.add("desktop.retire \(id)")
        retiredAt[id] = clock?()
        registered[id] = nil
        activeSizes[id] = nil
        onRetire?()
    }

    func reshape(_ id: DisplayID, to screen: DesktopScreen) async -> Bool {
        journal.add("desktop.reshape \(id) \(screen.width)x\(screen.height)")
        guard !reshapeFails, registered[id] != nil else { return false }
        registered[id] = screen
        activeSizes[id] = screen
        return true
    }

    func screen(_ id: DisplayID) -> DesktopScreen? { registered[id] }

    func size(_ id: DisplayID) -> DesktopScreen? { activeSizes[id] }

    func setSize(_ id: DisplayID, _ screen: DesktopScreen) async {
        journal.add("desktop.setSize \(id) \(screen.width)x\(screen.height)")
        guard !setSizeFails, registered[id] != nil else { return }
        activeSizes[id] = screen
    }

    func bounds(_ id: DisplayID) -> CGRect? {
        if let extra = extraBounds[id] { return extra }
        guard let s = activeSizes[id] else { return nil }
        return CGRect(origin: Self.origin, size: s.size)
    }

    func windowArea(_ id: DisplayID) -> CGRect? {
        guard let s = activeSizes[id] else { return nil }
        return CGRect(x: Self.origin.x, y: Self.origin.y + Self.menuBar,
                      width: CGFloat(s.width), height: CGFloat(s.height) - Self.menuBar)
    }

    func sourceArea(containing point: CGPoint, excluding: Set<DisplayID>) -> CGRect? {
        for (id, area) in physicalScreens where !excluding.contains(id) {
            let full = CGRect(x: area.minX, y: area.minY - Self.menuBar, width: area.width, height: area.height + Self.menuBar)
            if full.contains(point) { return area }
        }
        return Self.main
    }

    func mainArea() -> CGRect? { Self.main }
}

@MainActor
private final class DesktopRig {
    let tmp: TempDir
    let paths: SnugPaths
    let journal = Journal()
    let displays: FakeDesktopDisplays
    let windows: FakeWindows
    let timeline = ManualTimeline()
    let desk: DesktopDesk

    // 分布在 4 块物理屏上的代表窗口
    let codeWin = WindowInfo(key: WindowKey(pid: 21, id: 101), app: "Xcode", bundleID: "com.apple.dt.Xcode", title: "Snug")
    let browserWin = WindowInfo(key: WindowKey(pid: 22, id: 102), app: "Chrome", bundleID: "com.google.Chrome", title: "Docs")
    let fullWin = WindowInfo(key: WindowKey(pid: 23, id: 103), app: "Safari", bundleID: "com.apple.Safari", title: "PR")
    let portraitWin = WindowInfo(key: WindowKey(pid: 24, id: 104), app: "Ghostty", bundleID: "com.mitchellh.ghostty", title: "logs")
    let minimizedWin = WindowInfo(key: WindowKey(pid: 25, id: 105), app: "备忘录", bundleID: "com.apple.Notes", title: "草稿", minimized: true)

    let codeOrigin = CGRect(x: 80, y: 60, width: 1400, height: 900)                  // #1 内建屏
    let browserOrigin = CGRect(x: 1800, y: 40, width: 2400, height: 1350)            // #2 外接 2K 大窗
    let fullScreenFrame = CGRect(x: 4288, y: 0, width: 2560, height: 1440)           // #3 全屏空间
    let fullWindowedOrigin = CGRect(x: 4500, y: 120, width: 1600, height: 1000)      // #3 退出全屏后的原位
    let portraitOrigin = CGRect(x: -1400, y: -1200, width: 1360, height: 2200)       // #5 竖置副屏负坐标高窗
    let minimizedOrigin = CGRect(x: 2000, y: 200, width: 700, height: 500)           // #2 已最小化

    init(dataDirectory: URL? = nil) throws {
        let tmp = try TempDir()
        let dir = tmp.url
        self.tmp = tmp
        paths = SnugPaths(dataDirectory: dataDirectory ?? dir, logFile: dir.appendingPathComponent("Snug.log"))
        displays = FakeDesktopDisplays(journal: journal)
        windows = FakeWindows(journal: journal, ledger: paths.desktopRecord)
        windows.add(codeWin.key, frame: codeOrigin, info: codeWin)
        windows.add(browserWin.key, frame: browserOrigin, info: browserWin)
        windows.add(fullWin.key, frame: fullScreenFrame, fullScreen: true, windowed: fullWindowedOrigin, info: fullWin)
        windows.add(portraitWin.key, frame: portraitOrigin, info: portraitWin)
        windows.add(minimizedWin.key, frame: minimizedOrigin, minimized: true, info: minimizedWin)
        desk = DesktopDesk(displays: displays, windows: windows, timeline: timeline, paths: paths)
        let timeline = timeline
        displays.clock = { timeline.now }
        windows.clock.withLock { $0 = { timeline.now } }
    }

    var record: DesktopRecord? { RestoreRecord<DesktopRecord>(url: paths.desktopRecord).pending() }
}

@Suite("桌面屏调度 DesktopDesk")
@MainActor
struct DesktopDeskTests {
    @Test("刚连上未选桌面屏：建屏并保护物理屏窗口不被系统挪乱，但绝不提前聚拢窗口")
    func readyWithoutMovingWindowsUntilSelected() async throws {
        let rig = try DesktopRig()
        // 模拟加屏时 macOS 擅自把物理屏窗口晃动一下
        rig.displays.onCreate = {
            rig.windows.setFrame(rig.codeWin.key, CGRect(x: 300, y: 300, width: 1400, height: 900))
        }
        rig.desk.setWanted(true)
        await rig.desk.idle()

        let id = try #require(rig.desk.state.display)
        #expect(!rig.desk.state.gathered)
        #expect(rig.desk.state.gatheredCount == 0)
        #expect(rig.record == nil)
        // 4 扇非最小化窗口仍在各自的物理屏原位，连系统乱挪的那扇也被快照放回
        #expect(rig.windows.window(rig.codeWin.key)?.frame == rig.codeOrigin)
        #expect(rig.windows.window(rig.browserWin.key)?.frame == rig.browserOrigin)
        #expect(rig.windows.window(rig.fullWin.key)?.fullScreen == true)
        #expect(rig.windows.window(rig.portraitWin.key)?.frame == rig.portraitOrigin)
        _ = id
    }

    @Test("切屏即聚拢 + 断开即归位：4 块屏与全屏空间的窗口全部收拢进桌面屏可用区，先记账再动手，断开后分毫不差回原位")
    func autoGatherOnSelectAndLosslessRestoreOnDisconnect() async throws {
        let rig = try DesktopRig()
        rig.desk.setWanted(true)
        await rig.desk.idle()
        let id = try #require(rig.desk.state.display)
        let desktopArea = try #require(rig.displays.windowArea(id))
        rig.journal.clear()

        // 用户在 UU远程 里切到了「Snug 桌面屏」
        rig.desk.setContext(streaming: true)
        await rig.desk.idle()

        #expect(rig.desk.state.gathered)
        #expect(rig.desk.state.gatheredCount == 4)
        // 每一次挪窗口、退全屏前，账本都已经在盘上（带 ✎ 标记）
        let moves = rig.journal.all.filter { $0.hasPrefix("move ") || $0.hasPrefix("fullscreen ") }
        #expect(!moves.isEmpty)
        for entry in moves {
            #expect(entry.hasSuffix(" ✎"), "未记账先动了窗口：\(entry)")
        }

        // 4 扇窗口全部落在桌面屏可用区域内，超大窗口已夹紧，最小化窗口没被拉起
        for key in [rig.codeWin.key, rig.browserWin.key, rig.fullWin.key, rig.portraitWin.key] {
            let w = try #require(rig.windows.window(key))
            #expect(!w.fullScreen)
            #expect(desktopArea.contains(w.frame), "\(key) 越出了桌面屏可用区：\(w.frame)")
        }
        #expect(rig.windows.window(rig.minimizedWin.key)?.minimized == true)
        #expect(rig.windows.window(rig.minimizedWin.key)?.frame == rig.minimizedOrigin)
        // 最前面的窗口自动获得焦点，键盘快捷键立即可用
        #expect(rig.journal.all.contains("focus \(rig.codeWin.key.id)"))

        // 远控结束：全部归位到各自原来的物理屏坐标，全屏窗口恢复原生全屏，账本销账，桌面屏满 2.5s 后下线
        rig.desk.setWanted(false)
        await rig.desk.idle()

        #expect(rig.desk.state.screen == .off)
        #expect(!rig.desk.state.gathered)
        #expect(rig.desk.state.gatheredCount == 0)
        #expect(rig.record == nil)
        #expect(rig.windows.window(rig.codeWin.key)?.frame == rig.codeOrigin)
        #expect(rig.windows.window(rig.browserWin.key)?.frame == rig.browserOrigin)
        #expect(rig.windows.window(rig.fullWin.key)?.fullScreen == true)
        #expect(rig.windows.window(rig.fullWin.key)?.otherFrame == rig.fullWindowedOrigin)
        #expect(rig.windows.window(rig.portraitWin.key)?.frame == rig.portraitOrigin)

        let created = try #require(rig.displays.createdAt[id])
        let retired = try #require(rig.displays.retiredAt[id])
        #expect(retired - created >= DesktopScreenSpec.minimumLifetime)
    }

    @Test("使用期间在其它物理屏新弹出的对话框/窗口、或从程序坞还原的窗口自动拉上桌面屏，断开后同样归位")
    func pullsNewlySpawnedAndUnminimizedWindows() async throws {
        let rig = try DesktopRig()
        rig.desk.setWanted(true)
        await rig.desk.idle()
        let id = try #require(rig.desk.state.display)
        let desktopArea = try #require(rig.displays.windowArea(id))

        rig.desk.setContext(streaming: true)
        await rig.desk.idle()

        // 用户在桌面屏上自由把 codeWin 拖到了桌面屏内部另一个位置：syncWindows 绝不把它拽回去
        let userDragged = CGRect(x: desktopArea.minX + 40, y: desktopArea.minY + 30, width: 1000, height: 700)
        rig.windows.setFrame(rig.codeWin.key, userDragged)

        // 此时某 App 在 #3 物理屏新弹出了一个偏好设置窗口，同时用户在程序坞点开了备忘录（系统还原在 #2 物理屏）
        let popup = WindowInfo(key: WindowKey(pid: 29, id: 199), app: "Slack", bundleID: "com.tinyspeck.slackmacgap", title: "偏好设置")
        let popupOrigin = CGRect(x: 4800, y: 300, width: 680, height: 520)
        rig.windows.add(popup.key, frame: popupOrigin, info: popup)
        await rig.windows.setMinimized(rig.minimizedWin.key, false)

        rig.desk.syncWindows()
        await rig.desk.idle()

        #expect(rig.desk.state.gatheredCount == 6)
        #expect(rig.windows.window(rig.codeWin.key)?.frame == userDragged)
        #expect(desktopArea.contains(try #require(rig.windows.window(popup.key)).frame))
        #expect(desktopArea.contains(try #require(rig.windows.window(rig.minimizedWin.key)).frame))

        // 断开后新拉过来的窗口也都准确回到原来的 #3 和 #2 物理屏
        rig.desk.setWanted(false)
        await rig.desk.idle()
        #expect(rig.windows.window(popup.key)?.frame == popupOrigin)
        #expect(rig.windows.window(rig.minimizedWin.key)?.frame == rig.minimizedOrigin)
        #expect(rig.record == nil)
    }

    @Test("电脑与手机同时连着：放在手机屏上的窗口绝不被桌面屏抢走")
    func respectsPhoneScreenIsolation() async throws {
        let rig = try DesktopRig()
        let phoneDisplayID: DisplayID = 14
        let phoneBounds = CGRect(x: 9000, y: 0, width: 540, height: 950)
        rig.displays.extraBounds[phoneDisplayID] = phoneBounds
        rig.windows.setFrame(rig.portraitWin.key, CGRect(x: 9000, y: 25, width: 540, height: 897))

        rig.desk.setWanted(true)
        await rig.desk.idle()
        rig.desk.setContext(streaming: true, excludedDisplays: [phoneDisplayID], excludedWindows: [rig.portraitWin.key])
        await rig.desk.idle()

        // 只有其余 3 扇物理屏窗口被聚拢，手机屏上的窗口纹丝不动
        #expect(rig.desk.state.gatheredCount == 3)
        #expect(rig.windows.window(rig.portraitWin.key)?.frame == CGRect(x: 9000, y: 25, width: 540, height: 897))
    }

    @Test("崩溃恢复与写盘保护：账本写不进盘时绝不动窗口；崩溃残留账本在下次启动 recover() 时逐一归位")
    func crashRecoveryAndUnwritableLedgerSafety() async throws {
        // 1. 数据目录不可写时：拒绝挪动任何窗口
        let unwritableTmp = try TempDir()
        let blockedFile = unwritableTmp.url.appendingPathComponent("not-a-dir")
        try Data("x".utf8).write(to: blockedFile)
        let lockedRig = try DesktopRig(dataDirectory: blockedFile)
        lockedRig.desk.setWanted(true)
        await lockedRig.desk.idle()
        lockedRig.desk.setContext(streaming: true)
        await lockedRig.desk.idle()
        #expect(lockedRig.desk.state.gatheredCount == 0)
        #expect(lockedRig.windows.window(lockedRig.codeWin.key)?.frame == lockedRig.codeOrigin)

        // 2. 聚拢后模拟进程崩溃（桌面屏消失、窗口被系统甩到主屏），新进程启动 recover() 按磁盘账本归位
        let rig = try DesktopRig()
        rig.desk.setWanted(true)
        await rig.desk.idle()
        rig.desk.setContext(streaming: true)
        await rig.desk.idle()
        let saved = try #require(rig.record)
        #expect(saved.windows.count == 4)

        // 模拟重启后的新 DesktopDesk，此时窗口散落在主屏 (0, 25)
        let freshDesk = DesktopDesk(displays: rig.displays, windows: rig.windows, timeline: rig.timeline, paths: rig.paths)
        rig.windows.setFrame(rig.browserWin.key, CGRect(x: 0, y: 25, width: 1200, height: 800))
        rig.windows.setFrame(rig.portraitWin.key, CGRect(x: 40, y: 50, width: 1000, height: 800))
        freshDesk.recover()
        await freshDesk.idle()

        #expect(rig.record == nil)
        #expect(rig.windows.window(rig.browserWin.key)?.frame == rig.browserOrigin)
        #expect(rig.windows.window(rig.portraitWin.key)?.frame == rig.portraitOrigin)
        #expect(rig.windows.window(rig.fullWin.key)?.fullScreen == true)
    }

    @Test("在线切换桌面屏尺寸与模式拨回修复：缩小尺寸后自动夹回超界窗口，系统拨掉 2 倍模式后自动切回")
    func onlineReshapeAndRecheck() async throws {
        let rig = try DesktopRig()
        rig.desk.setScreen(DesktopScreen(width: 1920, height: 1080))
        rig.desk.setWanted(true)
        rig.desk.setContext(streaming: true)
        await rig.desk.idle()
        let id = try #require(rig.desk.state.display)
        #expect(rig.displays.size(id) == DesktopScreen(width: 1920, height: 1080))

        // 在线改小到 1440×900：窗口自动收进 1440×875 可用区内
        let smaller = DesktopScreen(width: 1440, height: 900)
        rig.desk.setScreen(smaller)
        await rig.desk.idle()
        let newArea = try #require(rig.displays.windowArea(id))
        #expect(newArea.size == CGSize(width: 1440, height: 875))
        #expect(newArea.contains(try #require(rig.windows.window(rig.browserWin.key)).frame))

        // 系统把模式拨乱：displaysChanged 复查后自动切回 1440×900
        rig.displays.activeSizes[id] = DesktopScreen(width: 1920, height: 1080)
        rig.desk.displaysChanged()
        await rig.desk.idle()
        #expect(rig.displays.size(id) == smaller)
    }
}

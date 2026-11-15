import CoreGraphics
import Foundation
import Testing
@testable import SnugCore

private let chat = AppInfo(bundleID: "com.openai.codex", name: "ChatGPT", path: "/Applications/ChatGPT.app")
private let ghosttyApp = AppInfo(bundleID: "com.mitchellh.ghostty", name: "Ghostty", path: "/Applications/Ghostty.app")
private let notesApp = AppInfo(bundleID: "com.apple.Notes", name: "备忘录", path: "/System/Applications/Notes.app")
private let chatHome = CGRect(x: 0, y: 33, width: 1512, height: 886)
/// Ghostty 新窗口：铺满主屏（已有全屏窗口时是原生全屏），退出全屏后是默认大小
private let ghosttyNew = CGRect(x: 0, y: 33, width: 1512, height: 949)
private let ghosttyNewWindowed = CGRect(x: 0, y: 350, width: 800, height: 632)

/// 只留下状态里「正在做什么」的变化，连续相同的算一次
@MainActor
private func recordWork(_ desk: PhoneDesk) -> () -> [PhoneDesk.Work?] {
    var works: [PhoneDesk.Work?] = []
    desk.onChange = { state in if works.last != .some(state.work) { works.append(state.work) } }
    return { works }
}

@Suite("App 资源库的动作 PhoneDesk")
@MainActor
struct PhoneDeskAppTests {
    @Test("启动没在跑的 App：等它的窗口出现在屏上（1.2 秒后才画出来），放上手机屏；先是「正在打开」，窗口出来转成「正在放」")
    func launch() async throws {
        let rig = try Rig()
        await rig.ready()
        rig.apps.willSpawn(chat, .init(id: 30, frame: chatHome, delay: 1.2))
        let works = recordWork(rig.desk)
        let started = rig.timeline.now
        rig.desk.open(chat)
        await rig.desk.idle()
        let window = WindowInfo(key: WindowKey(pid: 501, id: 30), app: chat.bundleID, bundleID: chat.bundleID, title: "")
        #expect(rig.journal.all == ["open com.openai.codex", "move 30 \(phoneArea.short) ✎", "focus 30"])
        #expect(rig.desk.state.placed?.window == window)
        #expect(rig.record?.original == chatHome)
        #expect(works() == [.opening(chat), .placing(window), nil])
        #expect(rig.timeline.now - started >= 1.2)
    }

    @Test("唤回在跑但没窗口的 App：App 重新显示原来那个窗口（编号不变）也认得出来")
    func reopenSameWindow() async throws {
        let rig = try Rig()
        await rig.ready()
        let key = WindowKey(pid: 600, id: 31)
        rig.apps.run(chat, pid: 600)
        rig.windows.add(key, frame: chatHome, hidden: true)
        rig.apps.willReshow(chat, id: 31)
        rig.desk.open(chat)
        await rig.desk.idle()
        #expect(rig.journal.all == ["open com.openai.codex", "move 31 \(phoneArea.short) ✎", "focus 31"])
        #expect(rig.desk.state.placed?.window.key == key)
    }

    @Test("新建窗口：按 ⌘N，新窗口放上手机屏、按默认级数放大字号；已经开着的窗口不会被误认成新窗口")
    func newWindow() async throws {
        let rig = try Rig()
        await rig.ready()
        rig.apps.run(ghosttyApp, pid: 10)
        rig.apps.willSpawn(ghosttyApp, .init(id: 40, frame: ghosttyNew, delay: 0.1))
        rig.desk.newWindow(RunningApp(pid: 10, app: ghosttyApp, windows: [ghostty]))
        await rig.desk.idle()
        #expect(rig.journal.all == ["newwin 10", "move 40 \(phoneArea.short) ✎", "focus 40", "zoom 40 +2 ✎"])
        #expect(rig.windows.window(ghostty.key)?.frame == ghosttyHome)
        #expect(rig.record?.original == ghosttyNew)
    }

    @Test("新窗口是原生全屏的（App 已有全屏窗口时新窗口也全屏）：先退出全屏再挪，原位记退出全屏后的位置，还原时恢复全屏")
    func newFullScreenWindow() async throws {
        let rig = try Rig()
        await rig.ready()
        rig.apps.run(ghosttyApp, pid: 10)
        rig.apps.willSpawn(ghosttyApp, .init(id: 40, frame: ghosttyNew, fullScreen: true, windowed: ghosttyNewWindowed))
        rig.desk.newWindow(RunningApp(pid: 10, app: ghosttyApp, windows: [ghostty]))
        await rig.desk.idle()
        #expect(Array(rig.journal.all.prefix(3)) == ["newwin 10", "fullscreen 40 off ✎", "move 40 \(phoneArea.short) ✎"])
        #expect(rig.record?.original == ghosttyNewWindowed)
        #expect(rig.record?.wasFullScreen == true)
    }

    @Test("新窗口开在手机屏上（App 记得上次在手机屏上的位置）：原位改记成主屏居中，屏撤了也放得回去")
    func bornOnPhone() async throws {
        let rig = try Rig()
        await rig.ready()
        let onPhone = CGRect(x: FakeDisplays.origin.x, y: 68, width: 540, height: 488)
        rig.apps.willSpawn(chat, .init(id: 30, frame: onPhone))
        rig.desk.open(chat)
        await rig.desk.idle()
        let main = FakeDisplays.main
        #expect(rig.record?.original == CGRect(x: (main.midX - 270).rounded(), y: (main.midY - 244).rounded(), width: 540, height: 488))
    }

    @Test("菜单里没有 ⌘N：提示没法新建窗口，什么都不动")
    func noNewWindow() async throws {
        let rig = try Rig()
        await rig.ready()
        rig.apps.run(notesApp, pid: 13)
        rig.desk.newWindow(RunningApp(pid: 13, app: notesApp, windows: []))
        await rig.desk.idle()
        #expect(rig.journal.all == ["newwin 13"])
        #expect(rig.desk.state.notice == .noNewWindow(app: "备忘录"))
        #expect(rig.desk.state.work == nil)
    }

    @Test("打不开（启动失败）：提示，什么都不动")
    func openFailed() async throws {
        let rig = try Rig()
        await rig.ready()
        rig.apps.launchFails.withLock { $0 = true }
        rig.desk.open(chat)
        await rig.desk.idle()
        #expect(rig.journal.all == ["open com.openai.codex"])
        #expect(rig.desk.state.notice == .openFailed(app: "ChatGPT"))
    }

    @Test("等满了也没有可显示的窗口：冷启动等 30 秒、唤回等 10 秒，然后提示未找到窗口")
    func noWindow() async throws {
        let rig = try Rig()
        await rig.ready()
        var started = rig.timeline.now
        rig.desk.open(chat)
        await rig.desk.idle()
        #expect(rig.desk.state.notice == .noWindow(app: "ChatGPT"))
        #expect(rig.timeline.now - started >= PhoneDesk.launchWait)
        #expect(rig.timeline.now - started < PhoneDesk.launchWait + 1)
        // 现在它在跑了：再点是唤回，只等 10 秒
        started = rig.timeline.now
        rig.desk.open(chat)
        await rig.desk.idle()
        #expect(rig.timeline.now - started >= PhoneDesk.windowWait)
        #expect(rig.timeline.now - started < PhoneDesk.windowWait + 1)
        #expect(rig.journal.all == ["open com.openai.codex", "open com.openai.codex"])
    }

    @Test("手机屏还没好：不打开，提示手机屏未就绪")
    func openWithoutScreen() async throws {
        let rig = try Rig()
        rig.desk.open(chat)
        await rig.desk.idle()
        #expect(rig.journal.all.isEmpty)
        #expect(rig.desk.state.notice == .screenNotReady)
    }

    @Test("退出：手机屏上放着它的窗口就先还原（缩回字号、回原位）再请它退出；退完不再盯，记录销账")
    func quitPlaced() async throws {
        let rig = try Rig()
        await rig.ready()
        rig.apps.run(ghosttyApp, pid: 10)
        await rig.pull(ghostty)
        rig.journal.clear()
        rig.desk.quit(RunningApp(pid: 10, app: ghosttyApp, windows: [ghostty]))
        #expect(rig.desk.state.quitting == [10])
        await rig.desk.idle()
        #expect(rig.journal.all == ["zoom 7 -2 ✎", "move 7 \(ghosttyHome.short) ✎", "quit 10"])
        #expect(rig.desk.state.quitting.isEmpty)
        #expect(rig.desk.state.placed == nil)
        #expect(rig.record == nil)
        #expect(await rig.apps.isRunning(pid: 10) == false)
    }

    @Test("退出时弹出「要存储吗」：把挂着对话框的那个窗口放上手机屏，在手机上就能选")
    func quitAsksToSave() async throws {
        let rig = try Rig()
        await rig.ready()
        rig.apps.run(notesApp, pid: 13)
        rig.apps.onQuit(notesApp, .asksToSave(notes.key.id))
        rig.desk.quit(RunningApp(pid: 13, app: notesApp, windows: [notes]))
        await rig.desk.idle()
        #expect(rig.journal.all.first == "quit 13")
        #expect(rig.journal.all.contains("move 10 \(phoneArea.short) ✎"))
        #expect(rig.desk.state.placed?.window.key == notes.key)
        #expect(rig.desk.state.quitting.isEmpty)
        #expect(rig.desk.state.notice == nil)
    }

    @Test("退出卡住：等满 10 秒还没退、也没有对话框，提示可以强制退出；强制退出后 App 没了")
    func quitStalls() async throws {
        let rig = try Rig()
        await rig.ready()
        rig.apps.run(chat, pid: 600)
        rig.apps.onQuit(chat, .stalls)
        let started = rig.timeline.now
        rig.desk.quit(RunningApp(pid: 600, app: chat, windows: []))
        await rig.desk.idle()
        #expect(rig.desk.state.notice == .quitStalled(app: "ChatGPT", pid: 600))
        #expect(rig.timeline.now - started >= PhoneDesk.quitWait)
        #expect(rig.desk.state.quitting.isEmpty)
        rig.desk.forceQuit(pid: 600, app: "ChatGPT")
        await rig.desk.idle()
        #expect(rig.journal.all == ["quit 600", "force 600"])
        #expect(rig.desk.state.notice == nil)
        #expect(await rig.apps.isRunning(pid: 600) == false)
    }

    @Test("退出时手机屏上它的窗口放不回去（App 卡住）：不退，提示无响应")
    func quitWhenStuck() async throws {
        let rig = try Rig()
        await rig.ready()
        rig.apps.run(ghosttyApp, pid: 10)
        await rig.pull(ghostty)
        rig.windows.blockMoves()
        rig.journal.clear()
        rig.desk.quit(RunningApp(pid: 10, app: ghosttyApp, windows: [ghostty]))
        await rig.desk.idle()
        #expect(!rig.journal.all.contains("quit 10"))
        #expect(rig.desk.state.notice == .windowUnresponsive(app: "Ghostty"))
        #expect(rig.desk.state.quitting.isEmpty)
        #expect(rig.desk.state.placed?.window == ghostty)
    }

    @Test("正在退的 App 再点退出：不重复请")
    func quitTwice() async throws {
        let rig = try Rig()
        await rig.ready()
        rig.apps.run(chat, pid: 600)
        let app = RunningApp(pid: 600, app: chat, windows: [])
        rig.desk.quit(app)
        rig.desk.quit(app)
        await rig.desk.idle()
        #expect(rig.journal.all == ["quit 600"])
    }
}

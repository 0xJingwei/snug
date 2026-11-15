// 桌面屏的调度中枢（电脑控制端连上多显示器 Mac 时的「虚拟拔线」模式）：
// 1. 电脑控制端连入时建一块横向 2 倍 HiDPI 的「Snug 桌面屏」，此时不动任何物理屏上的窗口；
// 2. 一旦检测到 UU 切到了「Snug 桌面屏」（切屏即聚拢），自动把所有物理屏和全屏空间里的非最小化窗口收拢过来，
//    大窗口按桌面屏可用区域夹紧尺寸，小窗口保持原大小；期间在其它物理屏冒出的新窗口、对话框或从程序坞还原的窗口也自动拉过来；
// 3. 每一扇窗口都是「先记账再动手」（写进 desktop-screen.json），远程断开、关掉开关或退出 Snug 时按账本逐一归位并恢复全屏，
//    归位成功或窗口已关闭才销账；崩溃残留由下次启动的 recover() 兜底还原
import CoreGraphics
import Foundation

@MainActor
public final class DesktopDesk {
    public struct State: Equatable, Sendable {
        public enum Screen: Equatable, Sendable {
            case off
            case preparing
            case ready(DisplayID)
            case failed
        }

        public var screen = Screen.off
        /// 本次会话是否已触发过聚拢（切到桌面屏后置为 true，断开或手动还原后回到 false）
        public var gathered = false
        /// 正在执行首次批量聚拢
        public var gathering = false
        /// 当前记在账本里、待归位的窗口数
        public var gatheredCount = 0
        /// 正在在线切换桌面屏分辨率
        public var reshaping = false

        public init() {}

        public var display: DisplayID? {
            if case .ready(let id) = screen { id } else { nil }
        }
    }

    static let recheckDelay: TimeInterval = 1.5
    static let settleDelay: TimeInterval = 0.3
    static let retryDelays: [TimeInterval] = [5, 15, 30]

    public private(set) var state = State() {
        didSet { if state != oldValue { onChange?(state) } }
    }
    public var onChange: ((State) -> Void)?
    /// 即将加屏、撤屏：通知会话层暂缓断开判定
    public var onTopologyChange: (() -> Void)?
    /// 设置里选定的桌面屏逻辑尺寸
    public private(set) var targetScreen: DesktopScreen

    private let displays: any DesktopDisplays
    private let windows: any WindowControl
    private let timeline: any Timeline
    private let ledger: RestoreRecord<DesktopRecord>
    private let lane = SerialLane()

    private var wanted = false
    private var streaming = false
    private var excludedDisplays: Set<DisplayID> = []
    private var excludedBounds: [CGRect] = []
    private var excludedWindows: Set<WindowKey> = []

    private var display: (id: DisplayID, bornAt: TimeInterval)?
    /// 当前由桌面屏接管的窗口账本（按聚拢顺序保存）
    private var records: [DesktopWindowRecord] = [] {
        didSet { state.gatheredCount = records.count }
    }
    private var recheckGeneration = 0
    private var pendingRecheck: Task<Void, Never>?
    private var failures = 0
    private var pendingRetry: Task<Void, Never>?
    private var syncing = false

    public init(displays: any DesktopDisplays, windows: any WindowControl, timeline: any Timeline = SystemTimeline(),
                paths: SnugPaths, screen: DesktopScreen = DesktopChoice.standard.screen) {
        self.displays = displays
        self.windows = windows
        self.timeline = timeline
        self.targetScreen = screen
        ledger = RestoreRecord(url: paths.desktopRecord)
    }

    // MARK: 意图

    /// 要不要桌面屏（会话、设置、权限合起来的结论）
    public func setWanted(_ on: Bool) {
        guard on != wanted else { return }
        wanted = on
        if !on {
            streaming = false
            cancelRetry()
        }
        lane.run { await self.reconcile() }
    }

    /// 更新「UU 此刻是否在推桌面屏」及需要避开的手机屏/窗口。一旦进入推流且尚未聚拢，自动收拢所有多屏窗口
    public func setContext(streaming: Bool, excludedDisplays: Set<DisplayID> = [], excludedBounds: [CGRect] = [],
                           excludedWindows: Set<WindowKey> = []) {
        let becameStreaming = streaming && !self.streaming
        self.streaming = streaming
        self.excludedDisplays = excludedDisplays
        self.excludedBounds = excludedBounds
        self.excludedWindows = excludedWindows
        guard becameStreaming, wanted, !state.gathered else { return }
        lane.run {
            guard self.wanted, self.streaming, !self.state.gathered, self.display != nil else { return }
            await self.gatherAll()
        }
    }

    /// 定期同步：销掉已关闭窗口的账；若用户正在用桌面屏，把在其它物理屏新弹出的窗口、对话框或刚从程序坞取消最小化的窗口拉过来
    public func syncWindows() {
        guard state.gathered, !state.gathering, !syncing else { return }
        syncing = true
        lane.run {
            defer { self.syncing = false }
            await self.pruneClosedRecords()
            guard self.wanted, self.streaming, self.state.gathered else { return }
            await self.pullStrayWindows()
        }
    }

    /// 手动把聚拢的窗口提前归位（不断开远控、不撤桌面屏；之后再切回桌面屏可再次触发聚拢）
    public func restoreWindows() {
        guard state.gathered || !records.isEmpty else { return }
        streaming = false
        lane.run {
            await self.restoreAll()
            self.state.gathered = false
        }
    }

    /// 设置里改了桌面屏尺寸：桌面屏在线就原地切换，并把超出新边界的窗口夹回屏内
    public func setScreen(_ screen: DesktopScreen) {
        guard screen.isValid, screen != targetScreen else { return }
        targetScreen = screen
        guard state.screen != .off else { return }
        if display != nil { state.reshaping = true }
        lane.run {
            defer { self.state.reshaping = false }
            guard let id = self.display?.id, self.displays.screen(id) != self.targetScreen else { return }
            self.state.reshaping = true
            await self.reshape(id)
        }
    }

    /// 屏幕组合变动后复查桌面屏的 2 倍模式有没有被系统或 UU 拨掉
    public func displaysChanged() {
        guard display != nil else { return }
        recheckGeneration += 1
        let generation = recheckGeneration
        pendingRecheck = Task {
            await timeline.sleep(Self.recheckDelay)
            guard generation == recheckGeneration else { return }
            lane.run { await self.recheck() }
        }
    }

    /// 启动或刚拿到辅助功能权限时：把上次崩溃残留没归位的窗口按账本放回原物理屏
    public func recover() {
        lane.run { await self.putBackLeftover() }
    }

    /// 退出前：归位所有窗口、撤掉桌面屏
    public func shutdown() async {
        wanted = false
        streaming = false
        cancelRetry()
        await lane.run { await self.reconcile() }.value
    }

    func idle() async {
        var retry: Task<Void, Never>?
        repeat {
            retry = pendingRetry
            await pendingRecheck?.value
            await retry?.value
            await lane.drain()
        } while pendingRetry != retry
    }

    // MARK: 加屏、撤屏

    private func reconcile() async {
        if wanted, display == nil {
            await addScreen()
        } else if !wanted, state.screen != .off || !records.isEmpty {
            await removeScreen()
        }
    }

    private func addScreen() async {
        state.screen = .preparing
        let before = await windows.snapshot()
        onTopologyChange?()
        do {
            let id = try await displays.create(targetScreen)
            display = (id, timeline.now)
            failures = 0
            await windows.restore(before, except: nil)
            state.screen = .ready(id)
            let modeText = displays.size(id).map { "\($0.width)×\($0.height)" } ?? "不是 2 倍"
            Log.info("桌面屏 #\(id) 已就绪（\(modeText)）")
            if streaming, !state.gathered {
                await gatherAll()
            }
        } catch {
            state.screen = .failed
            Log.error("加桌面屏失败：\(error)")
            scheduleRetry()
        }
    }

    private func scheduleRetry() {
        pendingRetry?.cancel()
        pendingRetry = nil
        guard failures < Self.retryDelays.count else {
            Log.error("加桌面屏连续失败 \(failures + 1) 次，这次远程不再重试")
            return
        }
        let delay = Self.retryDelays[failures]
        failures += 1
        Log.info("\(Int(delay)) 秒后重试加桌面屏（第 \(failures) 次重试）")
        pendingRetry = Task {
            await timeline.sleep(delay)
            guard !Task.isCancelled else { return }
            await lane.run { await self.reconcile() }.value
        }
    }

    private func cancelRetry() {
        pendingRetry?.cancel()
        pendingRetry = nil
        failures = 0
    }

    private func removeScreen() async {
        await restoreAll()
        state.gathered = false
        state.gathering = false
        await retireDisplay()
        state.screen = .off
    }

    private func retireDisplay() async {
        guard let (id, bornAt) = display else { return }
        let age = timeline.now - bornAt
        if age < DesktopScreenSpec.minimumLifetime {
            await timeline.sleep(DesktopScreenSpec.minimumLifetime - age)
        }
        let gone = displays.bounds(id)
        let before = await windows.snapshot()
        onTopologyChange?()
        await displays.retire(id)
        display = nil
        // 在桌面屏期间新开的窗口原本就在桌面屏上，撤屏后交给系统自动收回主屏，不往已消失的坐标放
        let elsewhere = gone.map { screen in before.filter { !screen.contains(CGPoint(x: $0.value.midX, y: $0.value.midY)) } }
        await windows.restore(elsewhere ?? before, except: nil)
        Log.info("已撤掉桌面屏 #\(id)")
    }

    private func reshape(_ id: DisplayID) async {
        guard await displays.reshape(id, to: targetScreen) else {
            Log.warn("桌面屏 #\(id) 没能换成 \(targetScreen.width)×\(targetScreen.height)，下次加屏时按新尺寸建")
            return
        }
        await clampWindowsOnDesktop(id)
    }

    private func recheck() async {
        guard let id = display?.id else { return }
        let expected = displays.screen(id) ?? targetScreen
        if displays.size(id) != expected {
            await displays.setSize(id, expected)
        }
        if state.gathered {
            await clampWindowsOnDesktop(id)
        }
    }

    // MARK: 聚拢与归位

    /// 首次切入桌面屏：先把上次残留账本结清，再把所有其它物理屏和全屏空间的非最小化窗口收拢到桌面屏
    private func gatherAll() async {
        guard let id = display?.id, let area = displays.windowArea(id), let desktopBounds = displays.bounds(id) else {
            Log.warn("聚拢窗口：桌面屏可放区域尚未就绪")
            return
        }
        await putBackLeftover()
        state.gathering = true
        state.gathered = true
        defer { state.gathering = false }

        let started = timeline.now
        let candidates = await windows.gatherableWindows()
        var movedCount = 0
        var frontmostToFocus: WindowKey?

        // 从后往前挪或保持原层次：WindowService.move 只改坐标尺寸、不 raise，不会打乱前后顺序；记下最前面的窗口最后激活
        for candidate in candidates {
            guard wanted else { break }
            guard !excludedWindows.contains(candidate.key) else { continue }
            guard let look = await windows.look(candidate.key), !look.minimized else { continue }
            let mid = CGPoint(x: look.frame.midX, y: look.frame.midY)
            if isOnExcludedDisplay(mid) { continue }
            if desktopBounds.contains(mid) {
                if frontmostToFocus == nil { frontmostToFocus = candidate.key }
                continue
            }
            let ok = await gatherOne(candidate, look: look, into: area, desktopID: id)
            if ok {
                movedCount += 1
                if frontmostToFocus == nil { frontmostToFocus = candidate.key }
            }
        }

        if let frontmost = frontmostToFocus {
            await windows.focus(frontmost)
        }
        let took = String(format: "%.1f", timeline.now - started)
        Log.info("桌面屏 #\(id) 已自动聚拢 \(movedCount) 个窗口（耗时 \(took)s）")
    }

    /// 桌面屏使用期间，把在其它物理屏上新开出的窗口、对话框或刚从程序坞还原的窗口自动拉到桌面屏并聚焦
    private func pullStrayWindows() async {
        guard let id = display?.id, let area = displays.windowArea(id), let desktopBounds = displays.bounds(id) else { return }
        let candidates = await windows.gatherableWindows()
        var newestPulled: WindowKey?
        for candidate in candidates {
            guard wanted, streaming else { break }
            guard !excludedWindows.contains(candidate.key) else { continue }
            guard let look = await windows.look(candidate.key), !look.minimized else { continue }
            let mid = CGPoint(x: look.frame.midX, y: look.frame.midY)
            if desktopBounds.contains(mid) || isOnExcludedDisplay(mid) { continue }
            if await gatherOne(candidate, look: look, into: area, desktopID: id) {
                Log.info("新出现在其它屏幕的 \(candidate.label) 已自动拉到桌面屏")
                if newestPulled == nil { newestPulled = candidate.key }
            }
        }
        if let key = newestPulled {
            await windows.focus(key)
        }
    }

    /// 单扇窗口记账并挪入桌面屏。严格「先写盘记账，再退全屏/改坐标」：写盘失败绝不动窗口
    private func gatherOne(_ window: WindowInfo, look: WindowLook, into targetArea: CGRect, desktopID: DisplayID) async -> Bool {
        let virtualIDs = excludedDisplays.union([desktopID])
        let initialOriginal = safeOriginalFrame(look.frame, virtualIDs: virtualIDs)
        let existedBefore = records.firstIndex { $0.window == window.key }

        if existedBefore == nil {
            let entry = DesktopWindowRecord(
                window: window.key, app: window.app, label: window.label,
                original: initialOriginal, wasFullScreen: look.fullScreen)
            records.append(entry)
            guard saveRecords() else {
                records.removeLast()
                return false
            }
        }

        var workingFrame = look.frame
        if look.fullScreen {
            await windows.setFullScreen(window.key, false)
            if let windowed = await windows.look(window.key)?.frame {
                workingFrame = windowed
                if let idx = records.firstIndex(where: { $0.window == window.key }) {
                    records[idx].original = safeOriginalFrame(windowed, virtualIDs: virtualIDs)
                    _ = saveRecords()
                }
            }
        }

        let source = displays.sourceArea(containing: CGPoint(x: workingFrame.midX, y: workingFrame.midY), excluding: virtualIDs)
        let target = DesktopLayout.fittedFrame(for: workingFrame, from: source, into: targetArea)
        guard await windows.move(window.key, to: target) != nil else {
            // 窗口中途关了就销账；如果还在只是挪不动，也没被我们挪走（除非退了全屏），按实际情况清理
            if await !windows.exists(window.key) {
                records.removeAll { $0.window == window.key }
                _ = saveRecords()
            } else if !look.fullScreen, existedBefore == nil {
                records.removeAll { $0.window == window.key }
                _ = saveRecords()
            }
            return false
        }
        return true
    }

    /// 桌面屏缩小分辨率后，把桌面屏上超出新可用区的窗口夹回屏内
    private func clampWindowsOnDesktop(_ id: DisplayID) async {
        guard let bounds = displays.bounds(id), let area = displays.windowArea(id) else { return }
        for record in records {
            guard let look = await windows.look(record.window), !look.minimized else { continue }
            guard bounds.contains(CGPoint(x: look.frame.midX, y: look.frame.midY)) else { continue }
            let clamped = DesktopLayout.fittedFrame(for: look.frame, from: area, into: area)
            if !look.frame.matches(clamped) {
                await windows.move(record.window, to: clamped)
            }
        }
    }

    private func pruneClosedRecords() async {
        var changed = false
        var kept: [DesktopWindowRecord] = []
        for record in records {
            if await windows.exists(record.window) {
                kept.append(record)
            } else {
                changed = true
            }
        }
        if changed {
            records = kept
            _ = saveRecords()
        }
    }

    /// 把当前账本里的所有窗口逐一放回原物理屏；仍然挪不动的留着账本等下次重试
    private func restoreAll() async {
        guard !records.isEmpty else { return }
        let current = records
        var stuck: [DesktopWindowRecord] = []
        for record in current {
            if let left = await putBackOne(record) {
                stuck.append(left)
            }
        }
        records = stuck
        _ = saveRecords()
        Log.info("桌面屏窗口归位完成：成功 \(current.count - stuck.count) 个\(stuck.isEmpty ? "" : "，暂未响应 \(stuck.count) 个留待稍后恢复")")
    }

    /// 恢复上次崩溃或未响应留下的磁盘账本
    private func putBackLeftover() async {
        guard records.isEmpty, let pending = ledger.pending(), !pending.windows.isEmpty else { return }
        Log.info("发现桌面屏上次未归位的 \(pending.windows.count) 个窗口，开始按记录恢复")
        var stuck: [DesktopWindowRecord] = []
        for record in pending.windows {
            guard await windows.exists(record.window) else { continue }
            if let left = await putBackOne(record) {
                stuck.append(left)
            }
        }
        records = stuck
        _ = saveRecords()
    }

    private func putBackOne(_ record: DesktopWindowRecord) async -> DesktopWindowRecord? {
        guard let got = await windows.move(record.window, to: record.original) else {
            if await windows.exists(record.window) {
                Log.warn("\(record.label) 还在，但暂时挪不回原位，保留还原记录")
                return record
            }
            return nil
        }
        if record.wasFullScreen {
            await timeline.sleep(Self.settleDelay)
            await windows.setFullScreen(record.window, true)
        }
        if !got.matches(record.original) {
            Log.warn("\(record.label) 归位尺寸略有偏差：目标 \(record.original.short)，实际 \(got.short)")
        }
        return nil
    }

    // MARK: 辅助

    private func isOnExcludedDisplay(_ point: CGPoint) -> Bool {
        if excludedBounds.contains(where: { $0.contains(point) }) { return true }
        for id in excludedDisplays {
            if let rect = displays.bounds(id), rect.contains(point) { return true }
        }
        return false
    }

    /// 若某扇窗口的原位恰好落在虚拟屏（手机屏或桌面屏）上，回退到主物理屏居中，避免虚拟屏撤掉后坐标悬空
    private func safeOriginalFrame(_ frame: CGRect, virtualIDs: Set<DisplayID>) -> CGRect {
        let mid = CGPoint(x: frame.midX, y: frame.midY)
        let onVirtual = isOnExcludedDisplay(mid) || virtualIDs.contains { displays.bounds($0)?.contains(mid) == true }
        guard onVirtual, let main = displays.mainArea() else { return frame }
        let size = CGSize(width: min(frame.width, main.width), height: min(frame.height, main.height))
        return CGRect(x: (main.midX - size.width / 2).rounded(), y: (main.midY - size.height / 2).rounded(),
                      width: size.width, height: size.height)
    }

    @discardableResult
    private func saveRecords() -> Bool {
        do {
            if records.isEmpty {
                try ledger.settle()
            } else {
                try ledger.record(DesktopRecord(windows: records))
            }
            return true
        } catch {
            Log.error("桌面屏还原记录写盘失败：\(error)")
            return false
        }
    }
}

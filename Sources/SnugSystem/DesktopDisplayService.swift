// 桌面屏的建、撤与换分辨率（CGVirtualDisplay 私有接口）。
// 与手机屏一样：物理尺寸按 220ppi 折算、上线后通过短命帮手进程（Snug --set-mode）切到 2 倍 HiDPI，
// 确保释放时 0.1 秒内干净下线、不阻塞主进程
import AppKit
import CGVirtualDisplayBridge
import SnugCore

@MainActor
public final class DesktopDisplayService: DesktopDisplays {
    static let onlineTimeout: TimeInterval = 6
    static let offlineTimeout: TimeInterval = 10
    nonisolated static let helperTimeout: TimeInterval = 10
    static let screenUpdateTimeout: TimeInterval = 2
    static let modesTimeout: TimeInterval = 3

    private var displays: [DisplayID: CGVirtualDisplay] = [:]
    private var screens: [DisplayID: DesktopScreen] = [:]
    private let helper: URL
    public var remote = false
    private var persistOwed = false
    private var settling = false
    private var retiring: [DisplayID: (snapshot: PhysicalDisplaySnapshot, permanently: Bool)] = [:]
    private var retiringInFlight: Set<DisplayID> = []

    public init(helper: URL) { self.helper = helper }

    public func create(_ screen: DesktopScreen) async throws -> DisplayID {
        let physicalBefore = PhysicalDisplaySnapshot.capture()
        if remote { persistOwed = true }
        var madeAny = false
        for serial in DesktopScreenSpec.serials {
            guard let display = make(serial: serial, screen: screen) else {
                Log.warn("桌面屏（serial=\(serial)）建不出来，换备用身份")
                continue
            }
            madeAny = true
            let id = display.displayID
            displays[id] = display
            screens[id] = screen
            guard await wait(id, online: true, timeout: Self.onlineTimeout) else {
                Log.warn("桌面屏 #\(id)（serial=\(serial)）建好 \(Int(Self.onlineTimeout)) 秒没上线，换备用身份")
                await retire(id)
                continue
            }
            try? await Task.sleep(for: .seconds(0.8))
            if size(id) != screen { await setSize(id, screen) }
            await PhysicalDisplayGuard.restoreIfNeeded(physicalBefore, helper: helper, permanently: false)
            return id
        }
        throw madeAny ? DesktopScreenError.neverOnline : DesktopScreenError.createFailed
    }

    public func retire(_ id: DisplayID) async {
        guard displays[id] != nil else {
            Log.warn("要撤的桌面屏 #\(id) 不是本进程建的")
            return
        }
        let savedPhysical = PhysicalDisplaySnapshot.capture()
        let wasRemote = remote
        if wasRemote { persistOwed = true }
        retiringInFlight.insert(id)
        defer { retiringInFlight.remove(id) }
        autoreleasepool { displays[id] = nil }
        screens[id] = nil
        if await !wait(id, online: false, timeout: Self.offlineTimeout) {
            Log.warn("桌面屏 #\(id) 释放 \(Int(Self.offlineTimeout)) 秒后仍在线")
            retiring[id] = (savedPhysical, !wasRemote)
            return
        }
        try? await Task.sleep(for: .seconds(1))
        await PhysicalDisplayGuard.restoreIfNeeded(savedPhysical, helper: helper, permanently: !wasRemote)
    }

    /// 远程结束、桌面屏真正下线后补永久配置；锁屏时保留欠账，等唤醒再做。
    public func settlePhysicalDisplays() {
        guard !settling, retiringInFlight.isEmpty,
              !retiring.isEmpty || (persistOwed && !remote && displays.isEmpty) else { return }
        settling = true
        Task {
            defer { settling = false }
            for (id, saved) in retiring where !Self.isOnline(id) {
                retiring[id] = nil
                await PhysicalDisplayGuard.restoreIfNeeded(saved.snapshot, helper: helper, permanently: saved.permanently)
            }
            guard persistOwed, !remote, displays.isEmpty, retiring.isEmpty, retiringInFlight.isEmpty else { return }
            if await PhysicalDisplayGuard.persistCurrent(helper: helper, allowed: {
                !self.remote && self.displays.isEmpty && self.retiring.isEmpty && self.retiringInFlight.isEmpty
            }) {
                persistOwed = false
            }
        }
    }

    public func reshape(_ id: DisplayID, to screen: DesktopScreen) async -> Bool {
        guard let display = displays[id] else {
            Log.warn("要改尺寸的桌面屏 #\(id) 不是本进程建的")
            return false
        }
        let from = DisplayMode.describe(id)
        guard autoreleasepool(invoking: { display.apply(Self.settings(screen)) }) else {
            Log.warn("桌面屏 #\(id) 改尺寸时 apply 失败，保持原尺寸（\(from)）")
            return false
        }
        screens[id] = screen
        let listed = await poll(timeout: Self.modesTimeout, every: 0.1) {
            DisplayMode.hasHiDPI(id, width: screen.width, height: screen.height)
        }
        if !listed {
            Log.warn("桌面屏 #\(id) 换了模式表，\(Int(Self.modesTimeout)) 秒内系统没列出 \(screen.width)×\(screen.height) 的 2 倍模式，照样去切")
        }
        await setSize(id, screen)
        Log.info("桌面屏 #\(id) 已换成 \(screen.width)×\(screen.height)（原来 \(from)），现在 \(DisplayMode.describe(id))")
        return true
    }

    public func screen(_ id: DisplayID) -> DesktopScreen? { screens[id] }

    public func size(_ id: DisplayID) -> DesktopScreen? { DisplayMode.hiDPISize(id) }

    public func setSize(_ id: DisplayID, _ screen: DesktopScreen) async {
        guard screens[id] != nil else {
            Log.warn("要切模式的桌面屏 #\(id) 不是本进程建的")
            return
        }
        let from = DisplayMode.describe(id)
        let status = await runHelper(id, width: screen.width, height: screen.height)
        guard status == 0 else {
            Log.warn("桌面屏 #\(id) 切不到 \(screen.width)×\(screen.height)（帮手退出码 \(status.map(String.init) ?? "启动失败")），现在 \(DisplayMode.describe(id))")
            return
        }
        let switched = await poll(timeout: Self.screenUpdateTimeout, every: 0.05) {
            self.size(id) == screen
                && Screens.screen(for: id)?.frame.size == screen.size
        }
        if switched {
            Log.info("桌面屏 #\(id) 切到 2 倍 \(screen.width)×\(screen.height)（原来 \(from)）")
        } else {
            Log.warn("桌面屏 #\(id) 帮手已切模式，但 \(Int(Self.screenUpdateTimeout)) 秒内界面未同步，现在 \(DisplayMode.describe(id))")
        }
    }

    public func bounds(_ id: DisplayID) -> CGRect? {
        let rect = CGDisplayBounds(id)
        return rect.isEmpty ? nil : rect
    }

    public func windowArea(_ id: DisplayID) -> CGRect? {
        Screens.screen(for: id).map { Screens.axRect(fromAppKit: $0.visibleFrame) }
    }

    public func sourceArea(containing point: CGPoint, excluding: Set<DisplayID>) -> CGRect? {
        for nsScreen in NSScreen.screens {
            guard let id = Screens.displayID(of: nsScreen), !excluding.contains(id) else { continue }
            let full = Screens.axRect(fromAppKit: nsScreen.frame)
            if full.contains(point) {
                return Screens.axRect(fromAppKit: nsScreen.visibleFrame)
            }
        }
        return mainArea()
    }

    public func mainArea() -> CGRect? {
        Screens.primary.map { Screens.axRect(fromAppKit: $0.visibleFrame) }
    }

    // MARK: 内部

    private func make(serial: UInt32, screen: DesktopScreen) -> CGVirtualDisplay? {
        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.name = DesktopScreenSpec.name
        descriptor.maxPixelsWide = UInt32(DesktopScreenSpec.maxPixels.width)
        descriptor.maxPixelsHigh = UInt32(DesktopScreenSpec.maxPixels.height)
        descriptor.sizeInMillimeters = CGSize(width: DesktopScreenSpec.millimeters.width, height: DesktopScreenSpec.millimeters.height)
        descriptor.vendorID = DesktopScreenSpec.vendorID
        descriptor.productID = DesktopScreenSpec.productID
        descriptor.serialNum = serial
        guard let display = autoreleasepool(invoking: { CGVirtualDisplay(descriptor: descriptor) }) else { return nil }
        guard autoreleasepool(invoking: { display.apply(Self.settings(screen)) }) else {
            Log.warn("桌面屏（serial=\(serial)）apply 失败")
            return nil
        }
        return display
    }

    private static func settings(_ screen: DesktopScreen) -> CGVirtualDisplaySettings {
        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = true
        settings.modes = [CGVirtualDisplayMode(width: UInt(screen.width), height: UInt(screen.height), refreshRate: 60)]
        return settings
    }

    private func wait(_ id: DisplayID, online: Bool, timeout: TimeInterval) async -> Bool {
        await poll(timeout: timeout, every: 0.25) { Self.isOnline(id) == online }
    }

    private func poll(timeout: TimeInterval, every: Double, until done: () -> Bool) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while !done() {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return false }
            try? await Task.sleep(for: .seconds(every))
        }
        return true
    }

    private static func isOnline(_ id: DisplayID) -> Bool {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return false }
        return ids.prefix(Int(count)).contains(id)
    }

    private func runHelper(_ id: DisplayID, width: Int, height: Int) async -> Int32? {
        let process = Process()
        process.executableURL = helper
        process.arguments = ["--set-mode", "\(id)", "\(width)", "\(height)"]
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                Log.error("帮手进程起不来（\(helper.path)）：\(error)")
                continuation.resume(returning: nil)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.helperTimeout) {
                guard process.isRunning else { return }
                Log.error("帮手进程 \(Int(Self.helperTimeout))s 没退出（屏 #\(id)），结束它")
                process.terminate()
            }
        }
    }
}

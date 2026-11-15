// 手机屏 App 资源库的统一数据源：在跑的 App 和各自的窗口、本机装着的 App、App 图标，界面只从这里读，
// 控制器决定「点一个 App 做什么」也看这里。系统读取在 SnugSystem（AppService、WindowService）。
// 列表露着时每 1.5 秒刷新在跑的 App：每次露出来第一次按最近用过重排，之后只增删、不换位置（见 AppList.keepingOrder）；
// 装着的 App 每次露出来读一次。收起就停；正在放窗口时暂停（列表被盖住，刷了也看不见，还和搬窗口排同一条队）；
// 一次远程结束就清空，下次从头读
import AppKit
import Observation
import SnugCore
import SnugSystem

@MainActor
@Observable
final class AppCatalog {
    static let refreshInterval: TimeInterval = 1.5

    private(set) var running: [RunningApp]
    /// 字典序
    private(set) var installed: [InstalledApp]
    /// 第一次刷新完成前显示「正在读取」，不显示「没有」
    private(set) var loaded: Bool

    @ObservationIgnored private let apps: AppService?
    @ObservationIgnored private let windows: WindowService?
    @ObservationIgnored private var refreshing: Task<Void, Never>?
    @ObservationIgnored private var scanning: Task<Void, Never>?
    @ObservationIgnored private var paused = false
    @ObservationIgnored private var icons: [String: NSImage] = [:]

    init(apps: AppService, windows: WindowService) {
        self.apps = apps
        self.windows = windows
        running = []
        installed = []
        loaded = false
    }

    /// 渲染样例用：固定的内容，不刷新
    init(sample running: [RunningApp], installed: [InstalledApp], loaded: Bool = true) {
        apps = nil
        windows = nil
        self.running = running
        self.installed = AppList.sorted(installed)
        self.loaded = loaded
    }

    func startRefreshing() {
        guard refreshing == nil, let apps, let windows else { return }
        scanning = Task { [weak self] in
            let list = AppList.sorted(await apps.installed())
            guard let self, !Task.isCancelled, list != installed else { return }
            installed = list
        }
        refreshing = Task { [weak self] in
            var reorder = true
            while !Task.isCancelled {
                guard let self else { return }
                if !paused {
                    let fresh = await windows.withWindows(apps.running())
                    guard !Task.isCancelled else { return }
                    let next = reorder ? fresh : AppList.keepingOrder(of: running, updatedWith: fresh)
                    if next != running { running = next }
                    loaded = true
                    reorder = false
                }
                try? await Task.sleep(for: .seconds(Self.refreshInterval))
            }
        }
    }

    func stopRefreshing() {
        refreshing?.cancel()
        refreshing = nil
        scanning?.cancel()
        scanning = nil
    }

    /// 暂停、继续刷新：不重开，继续后也不重排
    func setPaused(_ on: Bool) { paused = on }

    /// 一次远程结束：停下、清空，下次露出时显示「正在读取」，不拿上次的旧列表
    func reset() {
        stopRefreshing()
        running = []
        loaded = false
    }

    /// 在跑的这个 App（找窗口所属的 App、点 App 时判断有没有窗口）
    func running(_ app: AppInfo) -> RunningApp? { running.first { $0.app.bundleID == app.bundleID } }

    /// 列表刷新拿到的最新样子（终端的标题跟着命令变），没有就用传进来的
    func latest(_ window: WindowInfo) -> WindowInfo {
        running.first { $0.pid == window.key.pid }?.windows.first { $0.key == window.key } ?? window
    }

    func icon(for app: AppInfo) -> NSImage {
        if let cached = icons[app.bundleID] { return cached }
        let icon = AppService.icon(for: app)
        icons[app.bundleID] = icon
        return icon
    }

    /// 窗口所属 App 的图标
    func icon(for window: WindowInfo) -> NSImage {
        let app = running.first { $0.pid == window.key.pid }?.app
            ?? AppInfo(bundleID: window.bundleID ?? "pid:\(window.key.pid)", name: window.app, path: nil)
        return icon(for: app)
    }
}

// 手机屏上的「App 资源库」：盖住整块手机屏（连这块屏上的菜单栏一起），看起来像手机上的原生 App。
// 顶部固定一行返回键（放着窗口时才有，那一行一直留着，有没有返回键内容都不跳）；
// 标题和搜索框跟着列表滚走，分段控件「运行中 / 全部」滚到顶就停住、一直看得见，滚回顶部时页眉完整恢复。
// - 运行中：当前窗口（字号、还原）+ 在跑的 App，窗口挂在各自的 App 下；App 卡片右侧是新建窗口、退出（退出要再点一下确认）
// - 全部：本机所有 App 的图标网格，按字典序，正在运行的下方有圆点
// - 搜索：点搜索框进入，空着时按字母分组列出全部 App，输入后搜 App 和窗口标题
// - 正在打开、正在放：整屏讲明是哪个 App、哪个窗口；出了问题：顶部写明出了什么事、怎么办
// 每次回到列表都从最上面看起。文字只用短词，图标全用 SF Symbols
import AppKit
import SnugCore
import SwiftUI

struct PhoneHomeView: View {
    let state: AppState
    let catalog: AppCatalog
    let search: PhoneSearch
    let intents: any PhoneIntents

    @State private var tab: Tab
    /// 点了退出、等再点一下确认的那个 App
    @State private var confirmingQuit: Int32?

    init(state: AppState, catalog: AppCatalog, search: PhoneSearch, intents: any PhoneIntents, tab: Tab = .running) {
        self.state = state
        self.catalog = catalog
        self.search = search
        self.intents = intents
        _tab = State(initialValue: tab)
    }

    enum Tab: CaseIterable, Identifiable {
        case running, all
        var id: Self { self }
        var title: String { self == .running ? "运行中" : "全部" }
    }

    private static let top = "top"
    private var phone: PhoneDesk.State { state.phone }

    var body: some View {
        ZStack {
            if search.active {
                SearchPage(catalog: catalog, search: search, intents: intents)
            } else {
                home
            }
            if let busy = BusyView.Content(phone.work, catalog: catalog) {
                BusyView(content: busy).transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: phone.work)
        .background(PhoneStyle.background)
        .onChange(of: phone.listVisible) { confirmingQuit = nil }
    }

    private var home: some View {
        VStack(spacing: 0) {
            backRow
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        header.id(Self.top)
                        SwiftUI.Section {
                            page.padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 24)
                        } header: {
                            TabPicker(selection: $tab)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(PhoneStyle.background)
                        }
                    }
                }
                .scrollIndicators(.never)
                .onChange(of: phone.listVisible) { _, visible in
                    if visible { proxy.scrollTo(Self.top, anchor: .top) }
                }
            }
        }
        .disabled(phone.work != nil)
    }

    /// 返回键那一行一直留着：有没有返回键，下面的内容都不跳
    private var backRow: some View {
        Group {
            if let placed = phone.placed {
                BackButton(app: placed.window.app) { intents.returnToPlaced() }
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: PhoneStyle.touchTarget)
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("App").font(PhoneStyle.largeTitle)
            Button { search.begin() } label: {
                SearchBar { Text("搜索 App").foregroundStyle(.secondary) }
            }
            .buttonStyle(PressableStyle())
            if let notice = phone.notice { NoticeBanner(notice: notice, intents: intents) }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    @ViewBuilder private var page: some View {
        switch tab {
        case .running: runningPage
        case .all: AllApps(catalog: catalog, intents: intents)
        }
    }

    private var runningPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let placed = phone.placed {
                TitledSection("当前窗口") {
                    CurrentWindowCard(placed: placed, window: catalog.latest(placed.window), icon: catalog.icon(for: placed.window),
                                      work: phone.work, intents: intents)
                }
            }
            if !catalog.loaded {
                EmptyState(symbol: nil, text: "正在读取")
            } else if catalog.running.isEmpty {
                EmptyState(symbol: "square.grid.2x2", text: "没有正在运行的 App")
            } else if phone.placed != nil {
                TitledSection("其他 App") { appCards }
            } else {
                appCards
            }
        }
    }

    private var appCards: some View {
        LazyVStack(spacing: 12) {
            ForEach(catalog.running) { app in
                AppCard(app: app, placed: phone.placed?.window.key, quitting: phone.quitting.contains(app.pid),
                        confirming: $confirmingQuit, icon: catalog.icon(for: app.app), intents: intents)
            }
        }
    }
}

/// 搜索状态：点搜索框进入，取消、或从结果里打开了东西就退出。搜索时列表面板临时接收键盘（见 PhoneScreenWindows）
@MainActor
@Observable
final class PhoneSearch {
    private(set) var active = false
    var query = ""

    func begin() { active = true }

    func end() {
        active = false
        query = ""
    }
}

// MARK: 页眉

/// 分段控件：和 iOS 的一样，选中的那段浮起来
private struct TabPicker: View {
    @Binding var selection: PhoneHomeView.Tab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PhoneHomeView.Tab.allCases) { tab in
                Button { selection = tab } label: {
                    Text(tab.title)
                        .font(PhoneStyle.label.weight(selection == tab ? .semibold : .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background {
                            if selection == tab {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(PhoneStyle.segment)
                                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(PhoneStyle.fill, in: RoundedRectangle(cornerRadius: PhoneStyle.cornerRadius, style: .continuous))
        .animation(.easeOut(duration: 0.15), value: selection)
    }
}

/// 搜索框的样子（首页上是个按钮，搜索页里是真的输入框）
private struct SearchBar<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            content
            Spacer(minLength: 0)
        }
        .font(PhoneStyle.body)
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(PhoneStyle.fill, in: RoundedRectangle(cornerRadius: PhoneStyle.cornerRadius, style: .continuous))
    }
}

/// 回到手机屏上的窗口：和 iPhone 左上角「‹ App 名」回到上一个 App 一样
private struct BackButton: View {
    let app: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left").font(PhoneStyle.headline)
                Text(app).font(PhoneStyle.body.weight(.medium)).lineLimit(1)
            }
            .foregroundStyle(PhoneStyle.tint)
            .padding(.leading, 16)
            .padding(.trailing, 20)
            .frame(height: PhoneStyle.touchTarget)
            .background(PhoneStyle.tint.opacity(0.12), in: Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("返回 \(app)")
    }
}

/// 出了什么事、怎么办；没退出的 App 给「稍后 / 强制退出」
private struct NoticeBanner: View {
    let notice: PhoneDesk.Notice
    let intents: any PhoneIntents

    var body: some View {
        let text = notice.text
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(text.headline).font(PhoneStyle.body.weight(.semibold))
                if let detail = text.detail {
                    Text(detail).font(PhoneStyle.body).foregroundStyle(.secondary)
                }
                if case .quitStalled(let app, let pid) = notice {
                    HStack(spacing: 12) {
                        PillButton(title: "稍后") { intents.dismissNotice() }
                        PillButton(title: "强制退出", role: .destructive) { intents.forceQuit(pid: pid, app: app) }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .font(PhoneStyle.body)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: 运行中

/// 在跑的一个 App 和它的窗口（放在手机屏上的那个窗口不在这里，在「当前窗口」里）
private struct AppCard: View {
    let app: RunningApp
    let placed: WindowKey?
    let quitting: Bool
    @Binding var confirming: Int32?
    let icon: NSImage
    let intents: any PhoneIntents

    private var windows: [WindowInfo] { app.windows.filter { $0.key != placed } }
    private var asking: Bool { confirming == app.pid }

    private var subtitle: String {
        if asking { return "退出 \(app.app.name)？" }
        if quitting { return "正在退出" }
        if app.windows.isEmpty { return "没有窗口" }
        return windows.isEmpty ? "没有其他窗口" : "\(windows.count) 个窗口"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    confirming = nil
                    intents.open(app.app)
                } label: {
                    HStack(spacing: 16) {
                        AppIcon(image: icon, size: PhoneStyle.iconSize)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(app.app.name).font(PhoneStyle.headline).lineLimit(1)
                            Text(subtitle).font(PhoneStyle.body).foregroundStyle(asking ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .disabled(quitting)
                actions
            }
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .padding(.vertical, 12)
            ForEach(windows) { window in
                Divider().padding(.leading, 80)
                WindowRow(window: window) { intents.pull(window) }
                    .disabled(quitting)
            }
        }
        .card()
    }

    @ViewBuilder private var actions: some View {
        if quitting {
            ProgressView().controlSize(.small).frame(width: PhoneStyle.touchTarget)
        } else if asking {
            HStack(spacing: 8) {
                PillButton(title: "取消") { confirming = nil }
                PillButton(title: "退出", role: .destructive) {
                    confirming = nil
                    intents.quit(app)
                }
            }
        } else {
            HStack(spacing: 8) {
                RoundButton(symbol: "macwindow.badge.plus", label: "新建窗口") { intents.newWindow(app) }
                RoundButton(symbol: "xmark.app", label: "退出") { confirming = app.pid }
            }
        }
    }
}

/// App 卡片里的一个窗口：点一下放上手机屏
private struct WindowRow: View {
    let window: WindowInfo
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: "macwindow")
                    .font(PhoneStyle.headline.weight(.regular))
                    .foregroundStyle(.secondary)
                    .frame(width: PhoneStyle.iconSize)
                Text(window.title.isEmpty ? "无标题" : window.title).font(PhoneStyle.body).lineLimit(1)
                Spacer(minLength: 8)
                if window.minimized {
                    Text("已最小化")
                        .font(PhoneStyle.label)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(PhoneStyle.background, in: Capsule())
                }
            }
            .padding(.horizontal, 16)
            .frame(height: PhoneStyle.touchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

/// 手机屏上当前的窗口和它的字号、还原。
/// 分两行（操作在下面一行）；这个 App 不能调字号、只剩一个按钮时排成一行
private struct CurrentWindowCard: View {
    let placed: PhoneDesk.Placed
    /// 显示用的窗口（标题是最新的）
    let window: WindowInfo
    let icon: NSImage
    let work: PhoneDesk.Work?
    let intents: any PhoneIntents

    var body: some View {
        Group {
            if placed.zoomable {
                VStack(spacing: 0) {
                    row
                    Divider().padding(.leading, 16)
                    controls
                }
            } else {
                HStack(spacing: 0) {
                    row
                    controls.fixedSize()
                }
            }
        }
        .card()
    }

    private var row: some View {
        HStack(spacing: 16) {
            AppIcon(image: icon, size: PhoneStyle.iconSize)
            VStack(alignment: .leading, spacing: 4) {
                Text(window.app).font(PhoneStyle.headline).lineLimit(1)
                Text(window.title.isEmpty ? "无标题" : window.title).font(PhoneStyle.body).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
        }
        .padding(16)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            if placed.zoomable {
                RoundButton(symbol: "textformat.size.smaller", label: "缩小字号") { intents.zoom(by: -1) }
                    .disabled(placed.zoom <= ZoomBook.range.lowerBound)
                Text(zoomText)
                    .font(PhoneStyle.body.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 72)
                    .contentTransition(.numericText())
                RoundButton(symbol: "textformat.size.larger", label: "放大字号") { intents.zoom(by: 1) }
                    .disabled(placed.zoom >= ZoomBook.range.upperBound)
            }
            Spacer(minLength: 8)
            Button { intents.putBack() } label: {
                HStack(spacing: 8) {
                    if work == .puttingBack {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    Text("还原")
                }
                .font(PhoneStyle.body.weight(.medium))
                .padding(.horizontal, 20)
                .frame(height: PhoneStyle.touchTarget)
                .background(PhoneStyle.background, in: Capsule())
            }
            .buttonStyle(PressableStyle())
        }
        .padding(12)
    }

    private var zoomText: String {
        placed.zoom == 0 ? "默认字号" : "字号 \(placed.zoom > 0 ? "+" : "")\(placed.zoom)"
    }
}

// MARK: 全部

/// 本机所有 App：图标网格，4 列，按字典序；正在运行的下方有圆点
private struct AllApps: View {
    let catalog: AppCatalog
    let intents: any PhoneIntents

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 4)

    var body: some View {
        if catalog.installed.isEmpty {
            EmptyState(symbol: nil, text: "正在读取")
        } else {
            let running = Set(catalog.running.map(\.app.bundleID))
            LazyVGrid(columns: Self.columns, spacing: 20) {
                ForEach(catalog.installed) { item in
                    Button { intents.open(item.app) } label: {
                        VStack(spacing: 8) {
                            AppIcon(image: catalog.icon(for: item.app), size: 72)
                            Text(item.app.name).font(PhoneStyle.label).lineLimit(1).frame(maxWidth: 116)
                            Circle()
                                .fill(.secondary)
                                .frame(width: 6, height: 6)
                                .opacity(running.contains(item.app.bundleID) ? 1 : 0)
                                .padding(.top, -4)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }
}

// MARK: 搜索

private struct SearchPage: View {
    let catalog: AppCatalog
    @Bindable var search: PhoneSearch
    let intents: any PhoneIntents
    @FocusState private var focused: Bool

    private var query: String { search.query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                SearchBar {
                    TextField("搜索 App", text: $search.query)
                        .textFieldStyle(.plain)
                        .focused($focused)
                    if !search.query.isEmpty {
                        Button { search.query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清除")
                    }
                }
                Button("取消") { search.end() }
                    .buttonStyle(.plain)
                    .font(PhoneStyle.body)
                    .foregroundStyle(PhoneStyle.tint)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
            ScrollView {
                results.padding(.horizontal, 20).padding(.bottom, 24)
            }
            .scrollIndicators(.never)
        }
        // 面板在进入搜索时才成为键盘焦点，等它一拍再聚焦输入框
        .task {
            try? await Task.sleep(for: .milliseconds(50))
            focused = true
        }
    }

    @ViewBuilder private var results: some View {
        if query.isEmpty {
            alphabetical
        } else {
            let result = AppList.search(query, installed: catalog.installed, running: catalog.running)
            if result.isEmpty {
                EmptyState(symbol: "magnifyingglass", title: "无结果", text: "没有与「\(query)」相符的 App 或窗口")
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    if !result.apps.isEmpty {
                        TitledSection("App") { ListCard(result.apps) { appRow($0) } }
                    }
                    if !result.windows.isEmpty {
                        TitledSection("窗口") { ListCard(result.windows) { windowRow($0) } }
                    }
                }
            }
        }
    }

    /// 空着时：全部 App 按字母分组，数字、符号开头的归到最后的 #，同 iOS 的 App 资源库
    private var alphabetical: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(Self.groups(catalog.installed), id: \.letter) { group in
                Text(group.letter)
                    .font(PhoneStyle.label.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                    .padding(.top, 8)
                ListCard(group.apps.map(\.app)) { appRow($0) }
            }
        }
    }

    private static func groups(_ apps: [InstalledApp]) -> [(letter: String, apps: [InstalledApp])] {
        var groups: [(letter: String, apps: [InstalledApp])] = []
        var others: [InstalledApp] = []
        for app in apps {
            guard let first = app.keys.sortKey.first, first.isASCII, first.isLetter else {
                others.append(app)
                continue
            }
            let letter = first.uppercased()
            if groups.last?.letter == letter { groups[groups.count - 1].apps.append(app) } else { groups.append((letter, [app])) }
        }
        return others.isEmpty ? groups : groups + [("#", others)]
    }

    private func appRow(_ app: AppInfo) -> some View {
        let running = catalog.running(app)
        let subtitle = running.map { $0.windows.isEmpty ? "没有窗口" : "\($0.windows.count) 个窗口" } ?? "未打开"
        return ResultRow(icon: catalog.icon(for: app), title: app.name, subtitle: subtitle) {
            search.end()
            intents.open(app)
        }
    }

    private func windowRow(_ window: WindowInfo) -> some View {
        ResultRow(icon: catalog.icon(for: window), title: window.title.isEmpty ? "无标题" : window.title, subtitle: window.app) {
            search.end()
            intents.pull(window)
        }
    }
}

/// 一组结果放在一张卡片里，中间用分隔线隔开
private struct ListCard<Item: Identifiable, Row: View>: View {
    let items: [Item]
    let row: (Item) -> Row

    init(_ items: [Item], @ViewBuilder row: @escaping (Item) -> Row) {
        self.items = items
        self.row = row
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider().padding(.leading, 80) }
                row(item)
            }
        }
        .card()
    }
}

private struct ResultRow: View {
    let icon: NSImage
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                AppIcon(image: icon, size: PhoneStyle.iconSize)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(PhoneStyle.headline).lineLimit(1)
                    Text(subtitle).font(PhoneStyle.body).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: 正在打开、正在放

/// 整屏讲明正在打开哪个 App、放哪个窗口。窗口挪好列表就收起，失败了回到列表、顶部写明原因
private struct BusyView: View {
    struct Content: Equatable {
        let icon: NSImage
        let title: String
        let subtitle: String?

        @MainActor
        init?(_ work: PhoneDesk.Work?, catalog: AppCatalog) {
            switch work {
            case .opening(let app):
                (icon, title, subtitle) = (catalog.icon(for: app), app.name, nil)
            case .placing(let window):
                (icon, title, subtitle) = (catalog.icon(for: window), window.app, window.title.isEmpty ? nil : window.title)
            default:
                return nil
            }
        }
    }

    let content: Content

    var body: some View {
        VStack(spacing: 16) {
            AppIcon(image: content.icon, size: PhoneStyle.iconSize * 2)
            VStack(spacing: 4) {
                Text(content.title).font(PhoneStyle.headline).lineLimit(1)
                if let subtitle = content.subtitle {
                    Text(subtitle).font(PhoneStyle.body).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            VStack(spacing: 8) {
                ProgressView()
                Text("正在打开").font(PhoneStyle.label).foregroundStyle(.secondary)
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PhoneStyle.background)
    }
}

// MARK: 小部件

private struct AppIcon: View {
    let image: NSImage
    let size: CGFloat

    var body: some View {
        Image(nsImage: image).resizable().frame(width: size, height: size)
    }
}

private struct RoundButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(PhoneStyle.headline)
                .frame(width: PhoneStyle.touchTarget, height: PhoneStyle.touchTarget)
                .background(PhoneStyle.background, in: Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}

private struct PillButton: View {
    let title: String
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(PhoneStyle.body.weight(.medium))
                .foregroundStyle(role == .destructive ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .padding(.horizontal, 20)
                .frame(height: PhoneStyle.touchTarget)
                .background(role == .destructive ? AnyShapeStyle(.red) : AnyShapeStyle(PhoneStyle.background), in: Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}

/// 空的、正在读取、没找到：symbol 为 nil 时显示加载动画
private struct EmptyState: View {
    let symbol: String?
    var title: String?
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            if let symbol {
                Image(systemName: symbol).font(PhoneStyle.largeTitle).foregroundStyle(.tertiary)
            } else {
                ProgressView()
            }
            if let title { Text(title).font(PhoneStyle.headline) }
            Text(text).font(PhoneStyle.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

/// 列表里的一节：小标题 + 内容
private struct TitledSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(PhoneStyle.label)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            content
        }
    }
}

private extension View {
    func card() -> some View {
        background(PhoneStyle.card, in: RoundedRectangle(cornerRadius: PhoneStyle.cornerRadius, style: .continuous))
    }
}

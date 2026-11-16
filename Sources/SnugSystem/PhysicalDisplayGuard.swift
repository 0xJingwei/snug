// 保护实体显示器的分辨率与缩放模式：
// macOS WindowServer 按「当前在线的所有显示器组合（含虚拟屏）」分别记忆每块显示器的分辨率。
// 当虚拟屏加入形成 5 块屏的新组合（或旧的 5 屏组合里某块副屏曾记过另一档模式）时，系统会把那块实体副屏切到别的分辨率。
// 因此在建虚拟屏前拍下所有实体显示器的显示模式，建屏/撤屏后发现哪块实体屏被系统改了模式，就用短命帮手进程还原它。
import CoreGraphics
import Foundation
import SnugCore

public struct PhysicalDisplaySnapshot: Sendable {
    public struct Entry: Equatable, Sendable {
        public var id: DisplayID
        public var ioModeID: Int32
        public var width: Int
        public var height: Int
        public var pixelWidth: Int
        public var pixelHeight: Int
        public var refreshRate: Double

        var mode: ScreenMode {
            ScreenMode(ioModeID: ioModeID, width: width, height: height,
                       pixelWidth: pixelWidth, pixelHeight: pixelHeight, refreshRate: refreshRate)
        }
    }

    public var entries: [DisplayID: Entry]

    public static func capture() -> PhysicalDisplaySnapshot {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else {
            return PhysicalDisplaySnapshot(entries: [:])
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else {
            return PhysicalDisplaySnapshot(entries: [:])
        }
        var map: [DisplayID: Entry] = [:]
        for id in ids.prefix(Int(count)) {
            // 跳过 Snug 自己的虚拟屏（手机屏、桌面屏 vendorID 都是 0x534E）
            if CGDisplayVendorNumber(id) == UInt32(PhoneScreenSpec.vendorID) { continue }
            guard let mode = CGDisplayCopyDisplayMode(id) else { continue }
            map[id] = Entry(
                id: id,
                ioModeID: mode.ioDisplayModeID,
                width: mode.width,
                height: mode.height,
                pixelWidth: mode.pixelWidth,
                pixelHeight: mode.pixelHeight,
                refreshRate: mode.refreshRate
            )
        }
        return PhysicalDisplaySnapshot(entries: map)
    }

    /// 找出当前在线、但显示模式与快照不一致的实体显示器
    public func driftedDisplays() -> [Entry] {
        let now = Self.capture().entries
        var drifted: [Entry] = []
        for (id, saved) in entries {
            guard let current = now[id] else { continue }
            if !current.mode.isSame(as: saved.mode) {
                drifted.append(saved)
            }
        }
        return drifted.sorted { $0.id < $1.id }
    }
}

public enum PhysicalDisplayGuard {
    nonisolated static let helperTimeout: TimeInterval = 10

    /// 把被系统改掉模式的实体显示器逐块切回快照里的原始模式
    @MainActor
    public static func restoreIfNeeded(_ snapshot: PhysicalDisplaySnapshot, helper: URL, permanently: Bool) async {
        let drifted = snapshot.driftedDisplays()
        guard !drifted.isEmpty else { return }
        for entry in drifted {
            let before = DisplayMode.describe(entry.id)
            let status = await runHelper(helper: helper, entry: entry, permanently: permanently)
            if status == 0 {
                Log.info("实体屏 #\(entry.id) 分辨率被系统改动（\(before)），已恢复为 \(entry.width)x\(entry.height)pt/\(entry.pixelWidth)x\(entry.pixelHeight)px")
            } else {
                Log.warn("实体屏 #\(entry.id) 分辨率恢复未成功（帮手退出码 \(status.map(String.init) ?? "启动失败")），当前 \(DisplayMode.describe(entry.id))")
            }
        }
    }

    /// UU 结束后才把此刻模式写回永久配置，避免保存远程期间的临时刷新率。
    @MainActor
    public static func persistCurrent(helper: URL, allowed: @MainActor () -> Bool) async -> Bool {
        let snapshot = PhysicalDisplaySnapshot.capture()
        guard !snapshot.entries.isEmpty,
              snapshot.entries.keys.allSatisfy({ CGDisplayIsAsleep($0) == 0 }) else { return false }
        for entry in snapshot.entries.values.sorted(by: { $0.id < $1.id }) {
            guard allowed() else { return false }
            guard await runHelper(helper: helper, entry: entry, permanently: true) == 0 else { return false }
        }
        Log.info("桌面远程已结束，实体屏当前模式已写回永久配置")
        return true
    }

    @MainActor
    private static func runHelper(helper: URL, entry: PhysicalDisplaySnapshot.Entry, permanently: Bool) async -> Int32? {
        let process = Process()
        process.executableURL = helper
        process.arguments = ModeTarget.exact(entry.mode, permanently: permanently).arguments(display: entry.id)
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                Log.error("恢复实体屏帮手进程起不来（\(helper.path)）：\(error)")
                continuation.resume(returning: nil)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.helperTimeout) {
                guard process.isRunning else { return }
                Log.error("恢复实体屏帮手进程 \(Int(Self.helperTimeout))s 没退出（屏 #\(entry.id)），结束它")
                process.terminate()
            }
        }
    }
}

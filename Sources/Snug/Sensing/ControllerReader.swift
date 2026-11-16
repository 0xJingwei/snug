// 后台读 UU 的控制端表格：串行，同一时刻只有一次读取在跑（不堆积），读得太慢的结果丢弃。
// 结果放在加锁的盒子里，主线程每拍直接取，不经主队列转发：结果要是投回主线程、按到达时间判新鲜，
// 主线程一卡，后台早就读好的结果也会被当成过期，没有覆盖窗口的会话就会被误判断开
import Foundation
import os
import SnugCore
import SnugSystem

@MainActor
final class ControllerReader {
    /// 一次读取超过这么久就不可信（UU 卡住时 AX 每次调用最多等 1 秒，一棵树要调很多次）
    // 本机 UU 的完整界面树正常也要约 2.7 秒；仍在后台串行读，超过 5 秒的结果继续丢弃。
    nonisolated static let maxReadDuration: TimeInterval = 5

    private let queue = DispatchQueue(label: "com.zephyr4123.snug.ax-reader", qos: .utility)
    private let box = OSAllocatedUnfairLock(initialState: ControllerReadCache())

    /// 每拍调用：返回此刻可信的控制端表格，没有读取在跑就发起下一次
    func poll() -> ControllerTable {
        guard AX.isTrusted, let pid = UURemoteApp.pid() else {
            reset()
            return .unreadable
        }
        let now = Self.uptime()
        let (current, start, generation) = box.withLock { $0.poll(now: now) }
        if start { read(pid: pid, generation: generation) }
        return current
    }

    private func read(pid: pid_t, generation: Int) {
        let box = box
        queue.async {
            let started = Self.uptime()
            let windows = autoreleasepool { UUAccessibility.windows(pid: pid) }
            let took = Self.uptime() - started
            let tooSlow = took > Self.maxReadDuration
            if tooSlow {
                Log.warn(String(format: "读 UU 控制端表格用了 %.1fs，结果丢弃", took))
            }
            let table = tooSlow ? .unreadable : windows.map(ControllerTable.init(windows:)) ?? .unreadable
            box.withLock { $0.finish(table, generation: generation, now: Self.uptime()) }
        }
    }

    /// 没授权或 UU 没在运行：清空，在途的读取结果作废
    func reset() { box.withLock { $0.invalidate() } }

    private nonisolated static func uptime() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
}

import Foundation

/// 同一连接内复用5秒内的读取，跨连接作废缓存及在途结果。
public struct ControllerReadCache: Sendable {
    private var generation = 0
    private var inFlightGeneration: Int?
    private var latest = ControllerTable.unreadable
    private var publishedAt = -TimeInterval.infinity

    public init() {}

    public mutating func poll(now: TimeInterval) -> (current: ControllerTable, start: Bool, generation: Int) {
        let current = now - publishedAt <= 5 ? latest : .unreadable
        guard inFlightGeneration == nil else { return (current, false, generation) }
        inFlightGeneration = generation
        return (current, true, generation)
    }

    public mutating func finish(_ table: ControllerTable, generation expected: Int, now: TimeInterval) {
        guard inFlightGeneration == expected else { return }
        inFlightGeneration = nil
        guard generation == expected else { return }
        latest = table
        publishedAt = now
    }

    public mutating func invalidate() {
        generation += 1
        latest = .unreadable
    }
}

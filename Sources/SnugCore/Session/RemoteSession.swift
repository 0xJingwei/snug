// 会话层的组合：连接判定 + 会话生命周期，把每拍观测变成功能模块要处理的会话变化。
// 功能模块（手机屏）只消费会话状态，会话层不知道有哪些功能
import Foundation

public enum SessionTransition: Equatable, Sendable {
    /// 新会话开始
    case began(controllers: [String])
    /// 重连窗口内再连上，仍是同一会话
    case resumed(controllers: [String])
    case controllersChanged([String])
    /// 断开，进入重连窗口
    case interrupted
    /// 重连窗口过了，会话结束
    case ended
}

public struct RemoteSession: Sendable {
    public private(set) var tracker = ConnectionTracker()
    public private(set) var episode = SessionEpisode()
    /// 这次远程最后读到的控制端。断开那一拍 tracker 会清空，这里在重连窗口里照样记着
    public private(set) var episodeControllers: [String] = []
    /// 这次远程从什么时候开始；不在远程里是 nil
    public private(set) var episodeBeganAt: Date?

    public init() {}

    public var isConnected: Bool { tracker.isConnected }
    /// 此刻连着的控制端（断开时为空）
    public var controllers: [String] { tracker.controllers }
    public var inEpisode: Bool { episode.isActive }

    public mutating func update(_ signals: UUSignals, now: Date) -> [SessionTransition] {
        var out: [SessionTransition] = []
        if episode.advance(to: now) == .ended {
            out.append(.ended)
            episodeControllers = []
            episodeBeganAt = nil
        }
        switch tracker.update(signals, now: now) {
        case .connected(let names)?:
            if episode.connected(at: now) == .began {
                episodeBeganAt = now
                episodeControllers = names
                out.append(.began(controllers: names))
            } else {
                if !names.isEmpty { episodeControllers = names }
                out.append(.resumed(controllers: names))
            }
        case .controllersChanged(let names)?:
            episodeControllers = names
            out.append(.controllersChanged(names))
        case .disconnected?:
            if episode.disconnected(at: now) == .interrupted { out.append(.interrupted) }
        case nil:
            break
        }
        return out
    }

    public mutating func noteSelfInducedChange(at date: Date) {
        tracker.noteSelfInducedChange(at: date)
    }
}

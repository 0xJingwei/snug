import Foundation
import Testing
@testable import SnugCore

@Suite("控制端读取代次")
struct ControllerReadCacheTests {
    @Test("只有控制端表这一路证据时，正常3秒后台读取不会在两次读之间误判断开")
    func freshNamesBridgeNormalReadIntervals() {
        var cache = ControllerReadCache()
        var session = RemoteSession()
        var pending: (generation: Int, finish: Double)?
        for halfSecond in 0...24 {
            let now = Double(halfSecond) / 2
            if let read = pending, now >= read.finish {
                cache.finish(.shown(["MacBook Pro"]), generation: read.generation, now: now)
                pending = nil
            }
            let sample = cache.poll(now: now)
            if sample.start { pending = (sample.generation, now + 3) }
            let transitions = session.update(UUSignals(overlayVisible: false, controllers: sample.current, captureActive: nil), now: Date(timeIntervalSince1970: now))
            #expect(!transitions.contains(.interrupted))
        }
    }

    @Test("旧电脑读完后连接边界作废；在途旧读不会发布，也不会堆积读取")
    func connectionBoundaryInvalidatesOldComputer() {
        var cache = ControllerReadCache()
        let old = cache.poll(now: 0)
        cache.invalidate()
        #expect(!cache.poll(now: 1).start)
        cache.finish(.shown(["MacBook Pro"]), generation: old.generation, now: 2)
        let fresh = cache.poll(now: 2)
        #expect(fresh.current == .unreadable)
        #expect(fresh.start)
        cache.finish(.shown(["iPhone"]), generation: fresh.generation, now: 3)
        #expect(cache.poll(now: 3).current == .shown(["iPhone"]))
        #expect(cache.poll(now: 3.5).current == .shown(["iPhone"]))
        cache.invalidate()
        #expect(cache.poll(now: 3.6).current == .unreadable)
    }

    @Test("同一连接内只复用有效期内结果；长时间未更新则不再采信")
    func staleOrConsumedResultsAreNotReused() {
        var cache = ControllerReadCache()
        let first = cache.poll(now: 0)
        cache.finish(.shown(["MacBook Pro"]), generation: first.generation, now: 1)
        #expect(cache.poll(now: 2).current == .shown(["MacBook Pro"]))
        #expect(cache.poll(now: 2.5).current == .shown(["MacBook Pro"]))
        var stale = ControllerReadCache()
        let read = stale.poll(now: 0)
        stale.finish(.shown(["MacBook Pro"]), generation: read.generation, now: 1)
        #expect(stale.poll(now: 7).current == .unreadable)
    }
}

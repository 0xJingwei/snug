// 每拍合成一份对 UU远程 的观测：覆盖窗口（同步查）、控制端表格（后台读）、推流（日志子进程）
import Foundation
import SnugCore

/// 一拍的观测
struct UUSample: Equatable {
    var signals: UUSignals
    /// UU 此刻在推的屏（推流日志里解析出来的）；不知道就是 nil
    var streamingDisplay: DisplayID?
}

@MainActor
final class UUSensor {
    private let controllers = ControllerReader()
    private let captureLog = CaptureLogWatcher()

    private var lastCapture: Bool?
    private var lastOverlay = false

    func resetControllers() { controllers.reset() }

    func start() { captureLog.start() }
    func stop() { captureLog.stop() }

    /// now 是墙钟：推流日志的时间戳是墙钟
    func sample(now: Date) -> UUSample {
        let capture = captureLog.sample(at: now)
        let overlay = UURemoteApp.overlayVisible()
        if capture.active != lastCapture || overlay != lastOverlay { controllers.reset() }
        lastCapture = capture.active
        lastOverlay = overlay
        return UUSample(signals: UUSignals(overlayVisible: overlay,
                                           controllers: controllers.poll(),
                                           captureActive: capture.active),
                        streamingDisplay: capture.display)
    }
}

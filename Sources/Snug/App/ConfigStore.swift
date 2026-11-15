// config.json 的读写，只归 AppController 使用（全仓唯一写配置的地方）。
// 读：文件损坏时改名隔离再用默认值（不静默换默认值：那样下一次写盘就把原文件覆盖了）。
// 写：改副本，写盘成功才生效；写不进去就抛错，内存里保持原样，界面不会显示一个其实没存上的值
import Foundation
import SnugCore

@MainActor
final class ConfigStore {
    private let file: JSONFile<AppConfig>
    private(set) var config: AppConfig

    init(url: URL) {
        file = JSONFile(url: url)
        config = file.loadOrQuarantine() ?? AppConfig()
    }

    /// 交回是不是真的改了：值没变不写盘（拖滑块时同一档会反复设）
    @discardableResult
    func update(_ change: (inout AppConfig) throws -> Void) throws -> Bool {
        var next = config
        try change(&next)
        guard next != config else { return false }
        try file.save(next)
        config = next
        return true
    }
}

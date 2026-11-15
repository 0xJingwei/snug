// 手机型号：手机屏的比例按用户的手机屏幕算（见 ScreenFit）。
// 机型库 Assets/phone-models.json 是唯一的数据源，加机型只改它；这里只管解码、校验和查找。
// 用户选的那一台连同屏幕数值一起存进配置（PhoneChoice）：机型库以后改名、删条目，已经选好的不受影响
import Foundation

/// 一台手机的屏幕：竖握时的分辨率（像素，短边在前），Apple 设备另有逻辑宽度（点）。
/// 只看比例，所以自己填的也可以是比例（9 × 20 和 1080 × 2400 一样）
public struct PhoneScreen: Codable, Hashable, Sendable {
    public var width: Int
    public var height: Int
    /// 逻辑宽度（点）。只有 Apple 设备有公开数值；不知道时按 ScreenFit.assumedPoints 估
    public var points: Int?

    public init(width: Int, height: Int, points: Int? = nil) {
        self.width = width
        self.height = height
        self.points = points
    }

    /// 能用来算比例：都是正数，竖握（宽不大于高）
    public var isValid: Bool {
        width > 0 && height > 0 && width <= height && (points ?? 1) > 0
    }

    /// 自己填的分辨率或比例：横着填的（2400 × 1080）按竖握换过来；没填、不是正数、大得离谱的不收
    public static func custom(_ a: Int?, _ b: Int?) -> PhoneScreen? {
        let range = 1...20000
        guard let a, let b, range.contains(a), range.contains(b) else { return nil }
        return PhoneScreen(width: min(a, b), height: max(a, b))
    }
}

/// 机型库里的一台
public struct PhoneModel: Hashable, Sendable, Identifiable {
    public let brand: String
    public let name: String
    public let year: Int
    public let screen: PhoneScreen

    /// 品牌 + 型号，如「Apple iPhone 17 Pro Max」「华为 Mate 70 Pro」：选中后存进配置、显示在设置里的就是它
    public var id: String { "\(brand) \(name)" }
}

/// 用户选的手机：机型库里的一台，或自己填的分辨率
public struct PhoneChoice: Codable, Equatable, Sendable {
    /// 机型全名（PhoneModel.id）；自己填的为 nil
    public var model: String?
    public var screen: PhoneScreen

    public init(model: String?, screen: PhoneScreen) {
        self.model = model
        self.screen = screen
    }

    public init(_ model: PhoneModel) {
        self.init(model: model.id, screen: model.screen)
    }

    /// 没选过时用的：手机屏最早就是在这台上调出来的（540×950）。必须和机型库里的那一条一致（有测试盯着）
    public static let standard = PhoneChoice(model: "Apple iPhone 17 Pro Max", screen: PhoneScreen(width: 1320, height: 2868, points: 440))
}

public struct PhoneCatalog: Equatable, Sendable {
    public struct Brand: Equatable, Sendable, Identifiable {
        public let name: String
        /// 别名：英文名、拼音（「华为」也能用 huawei 搜到）
        public let aliases: [String]
        /// 按机型库里的顺序（新的在前）
        public let models: [PhoneModel]
        public var id: String { name }
    }

    public let brands: [Brand]

    public static let empty = PhoneCatalog(brands: [])

    init(brands: [Brand]) { self.brands = brands }

    /// 解码并校验机型库。不合格的条目整份拒收，并写明是哪一条、错在哪：机型库是随 App 发的，错了要在测试里拦下来
    public init(json: Data) throws {
        let file: File
        do {
            file = try JSONDecoder().decode(File.self, from: json)
        } catch {
            throw PhoneCatalogError("解不开：\(error)")
        }
        var seen = Set<String>()
        brands = try file.brands.map { brand in
            guard !brand.name.isEmpty, !brand.models.isEmpty else { throw PhoneCatalogError("品牌「\(brand.name)」没有名字或没有机型") }
            let models = try brand.models.map { entry in
                guard entry.screen.count == 2 else { throw PhoneCatalogError("\(brand.name) \(entry.name)：screen 要写成 [宽, 高]") }
                let model = PhoneModel(brand: brand.name, name: entry.name, year: entry.year,
                                       screen: PhoneScreen(width: entry.screen[0], height: entry.screen[1], points: entry.points))
                guard !entry.name.isEmpty, model.screen.isValid else {
                    throw PhoneCatalogError("\(model.id)：分辨率要是正数、按竖握写（短边在前）")
                }
                guard (2007...2100).contains(entry.year) else { throw PhoneCatalogError("\(model.id)：年份 \(entry.year) 不对") }
                guard seen.insert(Self.normalized(model.id)).inserted else { throw PhoneCatalogError("\(model.id)：重复了") }
                return model
            }
            return Brand(name: brand.name, aliases: brand.aliases ?? [], models: models)
        }
    }

    public init(contentsOf url: URL) throws {
        try self.init(json: try Data(contentsOf: url))
    }

    public var models: [PhoneModel] { brands.flatMap(\.models) }

    public func model(id: String) -> PhoneModel? {
        models.first { $0.id == id }
    }

    /// 按型号名、品牌名和别名找，不分大小写、不看空格（17promax、mate70、huawei mate 都行）。品牌整个命中就列出全部
    public func search(_ query: String) -> [Brand] {
        let q = Self.normalized(query)
        guard !q.isEmpty else { return brands }
        return brands.compactMap { brand in
            let names = ([brand.name] + brand.aliases).map(Self.normalized)
            let models = brand.models.filter { model in
                let name = Self.normalized(model.name)
                return names.contains { ($0 + name).contains(q) }
            }
            return models.isEmpty ? nil : Brand(name: brand.name, aliases: brand.aliases, models: models)
        }
    }

    static func normalized(_ text: String) -> String {
        text.lowercased().filter { !$0.isWhitespace }
    }

    /// 文件的样子：{"brands": [{"name", "aliases"?, "models": [{"name", "year", "screen": [宽, 高], "points"?}]}]}
    private struct File: Decodable {
        struct Brand: Decodable {
            let name: String
            let aliases: [String]?
            let models: [Model]
        }

        struct Model: Decodable {
            let name: String
            let year: Int
            let screen: [Int]
            let points: Int?
        }

        let brands: [Brand]
    }
}

public struct PhoneCatalogError: Error, Equatable, CustomStringConvertible {
    public let description: String
    init(_ description: String) { self.description = "机型库：\(description)" }
}

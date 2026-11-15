import Foundation
import Testing
@testable import SnugCore

@Suite("手机型号 PhoneCatalog")
struct PhoneModelsTests {
    /// 随 App 发的机型库（唯一的数据源）
    static let bundled = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Assets/phone-models.json")

    private func catalog(_ json: String) throws -> PhoneCatalog {
        try PhoneCatalog(json: Data(json.utf8))
    }

    private let sample = """
    {"brands": [
      {"name": "Apple", "models": [
        {"name": "iPhone 17 Pro Max", "year": 2025, "screen": [1320, 2868], "points": 440},
        {"name": "iPhone 17", "year": 2025, "screen": [1206, 2622], "points": 402}
      ]},
      {"name": "华为", "aliases": ["HUAWEI"], "models": [
        {"name": "Mate 70 Pro", "year": 2024, "screen": [1260, 2832]}
      ]}
    ]}
    """

    @Test("解码：品牌和机型按文件里的顺序，全名是品牌 + 型号，Apple 带逻辑宽度")
    func decode() throws {
        let c = try catalog(sample)
        #expect(c.brands.map(\.name) == ["Apple", "华为"])
        #expect(c.models.map(\.id) == ["Apple iPhone 17 Pro Max", "Apple iPhone 17", "华为 Mate 70 Pro"])
        #expect(c.model(id: "Apple iPhone 17")?.screen == PhoneScreen(width: 1206, height: 2622, points: 402))
        #expect(c.model(id: "华为 Mate 70 Pro")?.screen.points == nil)
    }

    @Test("不合格的整份拒收，写明是哪一条：横着写、型号重复、品牌重复、screen 不是两个数、没有机型")
    func rejects() {
        let bad = [
            #"{"brands":[{"name":"A","models":[{"name":"X","year":2024,"screen":[2400,1080]}]}]}"#,
            #"{"brands":[{"name":"A","models":[{"name":"X","year":2024,"screen":[1080,2400]},{"name":"x ","year":2024,"screen":[1080,2400]}]}]}"#,
            #"{"brands":[{"name":"A","models":[{"name":"X","year":2024,"screen":[1080]}]}]}"#,
            #"{"brands":[{"name":"A","models":[{"name":"X","screen":[1080,2400]}]},{"name":"a","models":[{"name":"Y","screen":[1080,2400]}]}]}"#,
            #"{"brands":[{"name":"A","models":[]}]}"#,
            #"{"brands":[{"name":"A","models":[{"name":"X","year":2024,"screen":[0,2400]}]}]}"#,
            "不是 JSON",
        ]
        for json in bad {
            #expect(throws: PhoneCatalogError.self) { try catalog(json) }
        }
    }

    @Test("搜索：不分大小写、不看空格，型号、品牌、别名都能搜；品牌整个命中列出全部；搜不到是空")
    func search() throws {
        let c = try catalog(sample)
        #expect(c.search("17promax").flatMap(\.models).map(\.name) == ["iPhone 17 Pro Max"])
        #expect(c.search(" IPHONE 17 ").flatMap(\.models).count == 2)
        #expect(c.search("huawei mate").flatMap(\.models).map(\.name) == ["Mate 70 Pro"])
        #expect(c.search("华为").flatMap(\.models).count == 1)
        #expect(c.search("").map(\.name) == ["Apple", "华为"])
        #expect(c.search("pixel").isEmpty)
    }

    @Test("自己填的：横着填的按竖握换过来，比例也行；没填、不是正数、大得离谱的不收")
    func custom() {
        #expect(PhoneScreen.custom(1080, 2400) == PhoneScreen(width: 1080, height: 2400))
        #expect(PhoneScreen.custom(2400, 1080) == PhoneScreen(width: 1080, height: 2400))
        #expect(PhoneScreen.custom(9, 20) == PhoneScreen(width: 9, height: 20))
        for (a, b) in [(nil, 2400), (1080, nil), (0, 2400), (-1, 2400), (1080, 99999)] as [(Int?, Int?)] {
            #expect(PhoneScreen.custom(a, b) == nil)
        }
    }

    @Test("随 App 发的机型库：读得出来、有足够多的机型")
    func bundledLoads() throws {
        let c = try PhoneCatalog(contentsOf: Self.bundled)
        #expect(c.brands.count >= 10)
        #expect(c.models.count >= 100)
    }

    @Test("默认的那台（PhoneChoice.standard）就是机型库里的一条，数值一致")
    func standardIsInCatalog() throws {
        let c = try PhoneCatalog(contentsOf: Self.bundled)
        let standard = try #require(PhoneChoice.standard.model)
        #expect(c.model(id: standard)?.screen == PhoneChoice.standard.screen)
    }

    @Test("机型库里 Apple 的都有逻辑宽度（比例按它算才准）")
    func bundledApplePoints() throws {
        let c = try PhoneCatalog(contentsOf: Self.bundled)
        for model in c.models where model.brand == "Apple" {
            #expect(model.screen.points != nil, "\(model.id)")
        }
    }

    @Test("配置里的那台按机型库现在的数值来：数值改了跟着改，改名删了用存下的，自己填的不动")
    func resolve() throws {
        let c = try catalog(sample)
        let stale = PhoneChoice(model: "华为 Mate 70 Pro", screen: PhoneScreen(width: 1200, height: 2700))
        #expect(c.resolve(stale).screen == PhoneScreen(width: 1260, height: 2832))
        let gone = PhoneChoice(model: "华为 Mate 60", screen: PhoneScreen(width: 1260, height: 2720))
        #expect(c.resolve(gone) == gone)
        let custom = PhoneChoice(model: nil, screen: PhoneScreen(width: 9, height: 20))
        #expect(c.resolve(custom) == custom)
    }
}

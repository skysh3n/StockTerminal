import Foundation

/// 假股票池：30 只真实 A 股代码/名称 + 基准价格（历史生成的起点）
public struct UniverseEntry: Sendable, Hashable {
    public let symbol: Symbol
    public let basePrice: Decimal

    public init(_ code: String, _ exchange: Exchange, _ name: String, _ basePrice: Decimal) {
        self.symbol = Symbol(code: code, exchange: exchange, name: name)
        self.basePrice = basePrice
    }
}

public enum MockSymbolUniverse {
    public static let entries: [UniverseEntry] = [
        UniverseEntry("600519", .sse, "贵州茅台", Decimal(1580)),
        UniverseEntry("300750", .szse, "宁德时代", Decimal(195)),
        UniverseEntry("002594", .szse, "比亚迪", Decimal(248)),
        UniverseEntry("601318", .sse, "中国平安", Decimal(48)),
        UniverseEntry("600036", .sse, "招商银行", Decimal(35)),
        UniverseEntry("000858", .szse, "五粮液", Decimal(128)),
        UniverseEntry("601012", .sse, "隆基绿能", Decimal(17)),
        UniverseEntry("600030", .sse, "中信证券", Decimal(22)),
        UniverseEntry("300059", .szse, "东方财富", Decimal(14)),
        UniverseEntry("600085", .sse, "同仁堂", Decimal(40)),
        UniverseEntry("000002", .szse, "万科A", Decimal(8)),
        UniverseEntry("000651", .szse, "格力电器", Decimal(38)),
        UniverseEntry("000333", .szse, "美的集团", Decimal(62)),
        UniverseEntry("600900", .sse, "长江电力", Decimal(28)),
        UniverseEntry("601888", .sse, "中国中免", Decimal(64)),
        UniverseEntry("600276", .sse, "恒瑞医药", Decimal(45)),
        UniverseEntry("300760", .szse, "迈瑞医疗", Decimal(258)),
        UniverseEntry("002475", .szse, "立讯精密", Decimal(32)),
        UniverseEntry("000725", .szse, "京东方A", Decimal(string: "4.20")!),
        UniverseEntry("600031", .sse, "三一重工", Decimal(17)),
        UniverseEntry("600309", .sse, "万华化学", Decimal(70)),
        UniverseEntry("601899", .sse, "紫金矿业", Decimal(17)),
        UniverseEntry("600887", .sse, "伊利股份", Decimal(27)),
        UniverseEntry("603288", .sse, "海天味业", Decimal(36)),
        UniverseEntry("603259", .sse, "药明康德", Decimal(48)),
        UniverseEntry("601995", .sse, "中金公司", Decimal(30)),
        UniverseEntry("688256", .sse, "寒武纪", Decimal(380)),
        UniverseEntry("600176", .sse, "中国巨石", Decimal(11)),
        UniverseEntry("601225", .sse, "陕西煤业", Decimal(22)),
        UniverseEntry("002230", .szse, "科大讯飞", Decimal(47)),
    ]

    public static var symbols: [Symbol] { entries.map(\.symbol) }

    /// 初始自选（前 12 只）
    public static let defaultWatchlist: [String] = Array(entries.prefix(12).map(\.symbol.fullCode))
}

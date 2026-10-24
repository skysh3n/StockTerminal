import Foundation

/// 交易工作区顶部指数条用的主要指数（腾讯 qt 快照；与个股同一套接口）。
public enum AShareIndices {
    public static let shanghai = Symbol(code: "000001", exchange: .sse, name: "上证指数")
    public static let shenzhen = Symbol(code: "399001", exchange: .szse, name: "深证成指")
    public static let chinext = Symbol(code: "399006", exchange: .szse, name: "创业板指")
    public static let csi300 = Symbol(code: "000300", exchange: .sse, name: "沪深300")
    public static let sse50 = Symbol(code: "000016", exchange: .sse, name: "上证50")
    public static let csi500 = Symbol(code: "000905", exchange: .sse, name: "中证500")
    public static let star50 = Symbol(code: "000688", exchange: .sse, name: "科创50")
    public static let bse50 = Symbol(code: "899050", exchange: .bse, name: "北证50")

    /// 指数条展示顺序（可横向滚动）。
    public static let all: [Symbol] = [
        shanghai, shenzhen, chinext, csi300, sse50, csi500, star50, bse50,
    ]

    public static var codes: [String] { all.map(\.fullCode) }
}

/// 指数条上额外展示的全球指数（腾讯公开行情；点选进「全球」详情）。
public enum StripGlobalIndices {
    public static let ids: [String] = ["hkHSI", "hkHSTECH", "usIXIC", "usDJI", "usINX"]

    public static var items: [GlobalIndex] {
        ids.compactMap { id in GlobalIndex.catalog.first { $0.id == id } }
    }
}

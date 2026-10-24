import Foundation

/// 交易工作区顶部指数条用的 A 股主要指数（腾讯代码与个股同一套快照接口）。
public enum AShareIndices {
    public static let shanghai = Symbol(code: "000001", exchange: .sse, name: "上证指数")
    public static let shenzhen = Symbol(code: "399001", exchange: .szse, name: "深证成指")
    public static let chinext = Symbol(code: "399006", exchange: .szse, name: "创业板指")

    public static let all: [Symbol] = [shanghai, shenzhen, chinext]

    public static var codes: [String] { all.map(\.fullCode) }
}

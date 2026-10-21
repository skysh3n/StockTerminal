import Foundation

/// K线增量更新事件：某标的某周期的最新 bar（可能是尾部替换，也可能是新 bar）
public struct KLineUpdate: Sendable, Hashable {
    public let symbol: String
    public let timeFrame: TimeFrame
    public let bar: KLine

    public init(symbol: String, timeFrame: TimeFrame, bar: KLine) {
        self.symbol = symbol
        self.timeFrame = timeFrame
        self.bar = bar
    }
}

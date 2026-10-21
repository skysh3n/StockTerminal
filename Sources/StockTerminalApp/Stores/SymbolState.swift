import Foundation
import Observation
import TradingCore

/// 单标的实时数据载体。
/// 性能核心：每只股票独立 @Observable 对象——Observation 按（实例, keypath）追踪失效，
/// 改某一只的 quote 只重绘「读了这只 state」的视图，绝不牵连整个自选列表。
@MainActor
@Observable
final class SymbolState {
    let symbol: Symbol
    var id: String { symbol.fullCode }

    var quote: Quote?
    var book: OrderBook?
    /// 逐笔成交（新→旧），上限 200 条防内存无界
    var ticks: [Tick] = []

    var preClose: Decimal? { quote?.preClose }

    init(_ symbol: Symbol) {
        self.symbol = symbol
    }

    func pushTick(_ t: Tick) {
        ticks.insert(t, at: 0)
        if ticks.count > 200 { ticks.removeLast(ticks.count - 200) }
    }
}

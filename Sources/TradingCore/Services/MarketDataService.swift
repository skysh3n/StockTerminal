import Foundation

/// 行情数据服务协议（跨平台预留的核心边界之一）。
///
/// 设计形态对齐真实行情 API：快照用 async 方法，推送用 AsyncStream。
/// 未来接真实券商/行情源时，只需实现本协议的 adapter
/// （WebSocket → AsyncStream、REST → async），UI 与 store 零改动。
public protocol MarketDataService: Sendable {
    /// 全量股票池（搜索用）
    func universe() async throws -> [Symbol]

    /// 全市场搜索（代码/名称），返回最多 limit 条 A 股
    func search(query: String, limit: Int) async throws -> [Symbol]

    /// 批量行情快照
    func quotes(for symbols: [String]) async throws -> [Quote]

    /// 历史 K 线（最近 count 根，含正在形成的尾部 bar）
    func history(symbol: String, timeFrame: TimeFrame, count: Int) async throws -> [KLine]

    /// 盘口快照
    func orderBook(symbol: String) async throws -> OrderBook

    /// 订阅行情快照流（多标的合并推送）
    func subscribeQuotes(symbols: [String]) -> AsyncStream<Quote>

    /// 订阅某标的某周期的 K 线增量更新流（每次推送最新 bar）
    func subscribeKLine(symbol: String, timeFrame: TimeFrame) -> AsyncStream<KLine>

    /// 订阅盘口流
    func subscribeOrderBook(symbol: String) -> AsyncStream<OrderBook>

    /// 订阅逐笔成交流
    func subscribeTicks(symbol: String) -> AsyncStream<Tick>
}

public extension MarketDataService {
    /// 便捷调用：默认取 10 条
    func search(query: String) async throws -> [Symbol] {
        try await search(query: query, limit: 10)
    }
}

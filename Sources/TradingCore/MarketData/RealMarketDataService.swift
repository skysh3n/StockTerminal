import Foundation

/// 真实行情数据服务：实现 MarketDataService 协议（腾讯快照/K线 + 东财逐笔）。
/// UI 与 store 完全无感——与 Mock 实现遵循同一协议，替换只发生在组合根（AppEnvironment）。
public struct RealMarketDataService: MarketDataService {
    private let universeSymbols: [Symbol]
    private let symbolsByCode: [String: Symbol]
    private let tencent = TencentMarketClient()
    private let eastmoney = EastmoneyTickClient()
    private let searchSession: URLSession

    public init(universe: [Symbol]) {
        self.universeSymbols = universe
        self.symbolsByCode = Dictionary(uniqueKeysWithValues: universe.map { ($0.fullCode, $0) })
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
        ]
        self.searchSession = URLSession(configuration: config)
    }

    /// 完整代码 → Symbol（前缀 SH/SZ/BJ + 6 位代码）。
    /// 搜索加入的股票不在初始股票池里，服务必须能动态解析任意 A 股代码。
    public static func parseFullCode(_ fullCode: String) -> Symbol? {
        guard fullCode.count == 8 else { return nil }
        let prefix = String(fullCode.prefix(2))
        let code = String(fullCode.suffix(6))
        guard code.allSatisfy(\.isNumber) else { return nil }
        let exchange: Exchange
        switch prefix {
        case "SH": exchange = .sse
        case "SZ": exchange = .szse
        case "BJ": exchange = .bse
        default: return nil
        }
        return Symbol(code: code, exchange: exchange, name: "")
    }

    private func resolve(_ fullCode: String) -> Symbol? {
        symbolsByCode[fullCode] ?? Self.parseFullCode(fullCode)
    }

    /// 连通性探测：成功拉到任一有效快照即认为可用
    public static func probe(symbol: Symbol) async -> Bool {
        let client = TencentMarketClient()
        do {
            let snaps = try await client.snapshots(for: [symbol])
            return snaps.first.map { $0.quote.lastPrice > 0 } ?? false
        } catch {
            return false
        }
    }

    private static func pollInterval(open: TimeInterval, closed: TimeInterval) -> TimeInterval {
        MarketSession.isOpen() ? open : closed
    }

    // MARK: - 快照查询

    public func universe() async throws -> [Symbol] { universeSymbols }

    /// 全市场搜索（东方财富 suggest 接口，A 股过滤）
    public func search(query: String, limit: Int) async throws -> [Symbol] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        guard let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://searchapi.eastmoney.com/api/suggest/get?input=\(encoded)&type=14&token=D43BF722C8E33BDC906FB84D85E326E8&count=\(max(limit, 20))")
        else { return [] }

        let (data, _) = try await searchSession.data(from: url)
        guard
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let table = json["QuotationCodeTable"] as? [String: Any],
            let rows = table["Data"] as? [[String: Any]]
        else { return [] }

        var out: [Symbol] = []
        for row in rows {
            guard (row["Classify"] as? String) == "AStock",
                  let code = row["Code"] as? String,
                  let name = row["Name"] as? String,
                  code.count == 6,
                  code.allSatisfy(\.isNumber),
                  let exchange = Self.exchange(forCode: code)
            else { continue }
            out.append(Symbol(code: code, exchange: exchange, name: name))
            if out.count >= max(limit, 20) { break }
        }
        return out
    }

    /// A股代码前缀 → 交易所（6 沪 / 0、3 深 / 4、8、92 北）
    static func exchange(forCode code: String) -> Exchange? {
        guard let first = code.first else { return nil }
        switch first {
        case "6": return .sse
        case "0", "3": return .szse
        case "4", "8", "9": return .bse   // 9 仅 920xxx 北交所新号段；沪B 900xxx 非 A 股已在分类阶段过滤
        default: return nil
        }
    }

    public func quotes(for symbols: [String]) async throws -> [Quote] {
        let syms = symbols.compactMap { resolve($0) }
        return try await tencent.snapshots(for: syms).map(\.quote)
    }

    public func orderBook(symbol: String) async throws -> OrderBook {
        guard let sym = resolve(symbol) else { throw ServiceError.symbolNotFound(symbol) }
        guard let snap = try await tencent.snapshots(for: [sym]).first else {
            throw ServiceError.backend("盘口获取失败")
        }
        return snap.book
    }

    // MARK: - 历史 K 线

    public func history(symbol: String, timeFrame: TimeFrame, count: Int) async throws -> [KLine] {
        guard let sym = resolve(symbol) else { throw ServiceError.symbolNotFound(symbol) }
        let period: TencentMarketClient.Period
        switch timeFrame {
        case .timeShare, .min1: period = .min1
        case .min5: period = .min5
        case .day: period = .day
        case .week: period = .week
        }
        let fetch = try await tencent.klines(for: sym, period: period, count: max(count, 240))
        var bars = fetch.bars
        if timeFrame == .timeShare {
            bars = Self.lastSessionBars(bars)
        }
        return Array(bars.suffix(count))
    }

    /// 分时只保留最近一个交易日的分钟序列
    static func lastSessionBars(_ bars: [KLine]) -> [KLine] {
        guard let last = bars.last else { return [] }
        let cal = MarketSession.shanghaiCalendar
        let lastDay = cal.startOfDay(for: last.timestamp)
        return bars.filter { cal.startOfDay(for: $0.timestamp) == lastDay }
    }

    // MARK: - 流式订阅（轮询 → AsyncStream）

    public func subscribeQuotes(symbols: [String]) -> AsyncStream<Quote> {
        let syms = symbols.compactMap { resolve($0) }
        let client = tencent
        let (stream, cont) = AsyncStream.makeStream(of: Quote.self, bufferingPolicy: .bufferingNewest(80))
        let task = Task {
            while !Task.isCancelled {
                if let snaps = try? await client.snapshots(for: syms) {
                    for snap in snaps { cont.yield(snap.quote) }
                }
                let iv = Self.pollInterval(open: 3, closed: 30)
                try? await Task.sleep(for: .seconds(iv))
            }
            cont.finish()
        }
        cont.onTermination = { _ in task.cancel() }
        return stream
    }

    public func subscribeOrderBook(symbol: String) -> AsyncStream<OrderBook> {
        guard let sym = resolve(symbol) else { return AsyncStream { $0.finish() } }
        let client = tencent
        let (stream, cont) = AsyncStream.makeStream(of: OrderBook.self, bufferingPolicy: .bufferingNewest(1))
        let task = Task {
            while !Task.isCancelled {
                if let snap = try? await client.snapshots(for: [sym]).first {
                    cont.yield(snap.book)
                }
                let iv = Self.pollInterval(open: 2, closed: 15)
                try? await Task.sleep(for: .seconds(iv))
            }
            cont.finish()
        }
        cont.onTermination = { _ in task.cancel() }
        return stream
    }

    public func subscribeTicks(symbol: String) -> AsyncStream<Tick> {
        guard let sym = resolve(symbol) else { return AsyncStream { $0.finish() } }
        let client = eastmoney
        let (stream, cont) = AsyncStream.makeStream(of: Tick.self, bufferingPolicy: .bufferingNewest(120))
        let task = Task {
            var emitted = Set<String>()
            var emittedOrder: [String] = []
            var seq: UInt64 = 0
            while !Task.isCancelled {
                if let rows = try? await client.recentTicks(symbol: sym, limit: 60) {
                    for t in rows {
                        let key = "\(t.timestamp.timeIntervalSince1970)-\(t.price)-\(t.volume)-\(t.direction.rawValue)"
                        guard !emitted.contains(key) else { continue }
                        emitted.insert(key)
                        emittedOrder.append(key)
                        seq += 1
                        let tick = Tick(id: seq, symbol: t.symbol, price: t.price,
                                        volume: t.volume, direction: t.direction, timestamp: t.timestamp)
                        cont.yield(tick)
                        if emittedOrder.count > 800 {
                            for old in emittedOrder.prefix(400) { emitted.remove(old) }
                            emittedOrder.removeFirst(400)
                        }
                    }
                }
                let iv = Self.pollInterval(open: 3, closed: 60)
                try? await Task.sleep(for: .seconds(iv))
            }
            cont.finish()
        }
        cont.onTermination = { _ in task.cancel() }
        return stream
    }

    public func subscribeKLine(symbol: String, timeFrame: TimeFrame) -> AsyncStream<KLine> {
        guard let sym = resolve(symbol) else { return AsyncStream { $0.finish() } }
        let client = tencent
        let period: TencentMarketClient.Period
        switch timeFrame {
        case .timeShare, .min1: period = .min1
        case .min5: period = .min5
        case .day: period = .day
        case .week: period = .week
        }
        let (stream, cont) = AsyncStream.makeStream(of: KLine.self, bufferingPolicy: .bufferingNewest(4))
        let task = Task {
            while !Task.isCancelled {
                if let fetch = try? await client.klines(for: sym, period: period, count: 3),
                   let lastBar = fetch.bars.last {
                    cont.yield(lastBar)
                }
                let iv = Self.pollInterval(open: 5, closed: 60)
                try? await Task.sleep(for: .seconds(iv))
            }
            cont.finish()
        }
        cont.onTermination = { _ in task.cancel() }
        return stream
    }
}

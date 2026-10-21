import Foundation
import Observation
import TradingCore

/// 行情总管：拥有全部 SymbolState 与 KLineSeries，管理服务订阅生命周期。
/// 只依赖 MarketDataService 协议——换真实行情源时本类零改动。
@MainActor
@Observable
final class MarketStore {
    private(set) var states: [String: SymbolState] = [:]
    private(set) var series: [String: KLineSeries] = [:]
    /// 当前图表对应的 series key："代码|周期"
    private(set) var activeKey: String?

    private let svc: any MarketDataService
    private var quoteTask: Task<Void, Never>?
    private var klineTask: Task<Void, Never>?
    private var bookTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var activeSymbolCode: String?

    // UI 级合流：高频流先入缓冲，按固定节拍批量落到 @Observable 状态，
    // 把主线程失效/重绘频率压到 3Hz（行情/盘口）与 2Hz（逐笔），
    // 引擎侧仍是 4Hz 全速——数据不丢，只是显示节拍收敛。
    private var pendingQuotes: [String: Quote] = [:]
    private var pendingBook: OrderBook?
    private var pendingTicks: [Tick] = []
    private var quoteFlushTask: Task<Void, Never>?
    private var bookFlushTask: Task<Void, Never>?
    private var tickFlushTask: Task<Void, Never>?

    init(_ svc: any MarketDataService) {
        self.svc = svc
    }

    var activeSeries: KLineSeries? {
        guard let key = activeKey else { return nil }
        return series[key]
    }

    func state(for code: String) -> SymbolState? { states[code] }

    /// 启动：建立全部标的状态、拉初始快照、订阅合并行情流
    func start(symbols: [Symbol]) async {
        for s in symbols where states[s.fullCode] == nil {
            states[s.fullCode] = SymbolState(s)
        }
        let codes = symbols.map(\.fullCode)
        if let quotes = try? await svc.quotes(for: codes) {
            for q in quotes { states[q.symbol]?.quote = q }
        }
        quoteTask?.cancel()
        restartQuoteSubscription()
    }

    /// 同步建档，让板块列表在下一帧就能画出名称。报价另补。
    func prepareSymbols(_ symbols: [Symbol]) {
        var created = false
        for symbol in symbols where states[symbol.fullCode] == nil {
            states[symbol.fullCode] = SymbolState(symbol)
            created = true
        }
        if created { restartQuoteSubscription() }
    }

    /// 把板块里尚未建档的标的放进状态表，并补一次快照。已有报价的不重复请求。
    func ensureSymbols(_ symbols: [Symbol]) async {
        prepareSymbols(symbols)
        let needQuote = symbols.map(\.fullCode).filter { states[$0]?.quote == nil }
        guard !needQuote.isEmpty, let quotes = try? await svc.quotes(for: needQuote) else { return }
        for quote in quotes { states[quote.symbol]?.quote = quote }
    }

    /// 动态标的建档：全市场搜索加入的新股票需要进 states 并扩展行情订阅
    func ensureSymbol(_ symbol: Symbol) {
        guard states[symbol.fullCode] == nil else { return }
        states[symbol.fullCode] = SymbolState(symbol)
        restartQuoteSubscription()
    }

    /// 以当前全部标的重建行情订阅（新增自选后调用）
    private func restartQuoteSubscription() {
        quoteTask?.cancel()
        let codes = Array(states.keys)
        guard !codes.isEmpty else { return }
        let stream = svc.subscribeQuotes(symbols: codes)
        quoteTask = Task { [weak self] in
            for await q in stream {
                guard let self else { break }
                self.pendingQuotes[q.symbol] = q
                self.scheduleQuoteFlush()
            }
        }
    }

    private func scheduleQuoteFlush() {
        guard quoteFlushTask == nil else { return }
        quoteFlushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self else { return }
            self.quoteFlushTask = nil
            let batch = self.pendingQuotes
            self.pendingQuotes = [:]
            for q in batch.values {
                self.states[q.symbol]?.quote = q
            }
        }
    }

    private func scheduleBookFlush(_ st: SymbolState) {
        guard bookFlushTask == nil else { return }
        bookFlushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self else { return }
            self.bookFlushTask = nil
            if let b = self.pendingBook {
                self.pendingBook = nil
                st.book = b
            }
        }
    }

    private func scheduleTickFlush(_ st: SymbolState) {
        guard tickFlushTask == nil else { return }
        tickFlushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard let self else { return }
            self.tickFlushTask = nil
            let batch = self.pendingTicks
            self.pendingTicks = []
            for t in batch.reversed() { st.pushTick(t) }
        }
    }

    /// 切换选中标的/周期：加载历史 + 重建对应订阅（旧 Task 全部取消，防泄漏与重复订阅）
    func select(symbol: Symbol, timeFrame: TimeFrame) async {
        let code = symbol.fullCode
        ensureSymbol(symbol)
        let key = "\(code)|\(timeFrame.rawValue)"
        activeKey = key

        // 1) K线历史 → series
        klineTask?.cancel()
        let preClose = states[code]?.quote?.preClose
        let history = (try? await svc.history(symbol: code, timeFrame: timeFrame, count: 800)) ?? []
        let s: KLineSeries
        if let existing = series[key] {
            s = existing
        } else {
            s = KLineSeries(symbol: code, timeFrame: timeFrame)
            series[key] = s
        }
        // 网络失败时保留已有数据，避免图表被清空
        if !history.isEmpty {
            s.load(history, preClose: preClose ?? history.last?.close)
        } else if s.isEmpty {
            s.load([], preClose: preClose)
        }

        // 2) K线增量流
        let kstream = svc.subscribeKLine(symbol: code, timeFrame: timeFrame)
        klineTask = Task { [weak self] in
            for await bar in kstream {
                guard let self, self.activeKey == key else { break }
                s.merge(bar)
            }
        }

        // 3) 盘口/逐笔：只在切换标的时重建
        if activeSymbolCode != code {
            activeSymbolCode = code
            bookTask?.cancel()
            tickTask?.cancel()
            guard let st = states[code] else { return }
            if st.book == nil { st.book = try? await svc.orderBook(symbol: code) }

            let bstream = svc.subscribeOrderBook(symbol: code)
            bookTask = Task { [weak self] in
                for await b in bstream {
                    guard let self, self.activeSymbolCode == code else { break }
                    self.pendingBook = b
                    self.scheduleBookFlush(st)
                }
            }
            let tstream = svc.subscribeTicks(symbol: code)
            tickTask = Task { [weak self] in
                for await t in tstream {
                    guard let self, self.activeSymbolCode == code else { break }
                    self.pendingTicks.append(t)
                    self.scheduleTickFlush(st)
                }
            }
        }
    }

    // 注：store 与 App 同生命周期，订阅 Task 由流终止/切换时取消，无需 deinit
    // （@MainActor 属性不能在 nonisolated deinit 中访问）
}

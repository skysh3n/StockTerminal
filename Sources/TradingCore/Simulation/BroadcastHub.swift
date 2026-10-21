import Foundation

/// 轻量多播枢纽：引擎侧 broadcast，订阅侧拿 AsyncStream。
/// NSLock 保证 Sendable；订阅/退订/广播均为 O(订阅数)。
/// 支持「过滤 + 变换」订阅（transform 返回 nil 即过滤掉）。
public final class BroadcastHub<Value: Sendable>: @unchecked Sendable {
    private struct Sink {
        let push: @Sendable (Value) -> Void
    }

    private let lock = NSLock()
    private var sinks: [UUID: Sink] = [:]

    public init() {}

    /// 订阅：transform 返回非 nil 时把结果推给下游流；返回 nil 即过滤。
    public func subscribe<T: Sendable>(
        bufferingPolicy: AsyncStream<T>.Continuation.BufferingPolicy = .unbounded,
        _ transform: @escaping @Sendable (Value) -> T?
    ) -> AsyncStream<T> {
        let (stream, continuation) = AsyncStream.makeStream(of: T.self, bufferingPolicy: bufferingPolicy)
        let id = UUID()
        lock.lock()
        sinks[id] = Sink(push: { value in
            if let mapped = transform(value) { continuation.yield(mapped) }
        })
        lock.unlock()
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            self.lock.lock()
            self.sinks[id] = nil
            self.lock.unlock()
        }
        return stream
    }

    /// 直接订阅原始值（可带过滤条件）
    public func stream(
        bufferingPolicy: AsyncStream<Value>.Continuation.BufferingPolicy = .unbounded,
        accept: @escaping @Sendable (Value) -> Bool = { _ in true }
    ) -> AsyncStream<Value> {
        subscribe(bufferingPolicy: bufferingPolicy) { accept($0) ? $0 : nil }
    }

    public func broadcast(_ value: Value) {
        lock.lock()
        let snapshot = Array(sinks.values)
        lock.unlock()
        for sink in snapshot { sink.push(value) }
    }

    public var subscriberCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return sinks.count
    }
}

/// 模拟撮合与行情源共用的广播通道。
/// 行情类流用 bufferingNewest：消费端（主线程）繁忙时自动合并只留最新值——
/// 状态型数据（报价/盘口/K线bar）丢中间帧无害；回报类流（委托/成交）用 unbounded 绝不丢。
public struct EventHubs: Sendable {
    public let quotes = BroadcastHub<Quote>()
    public let klines = BroadcastHub<KLineUpdate>()
    public let books = BroadcastHub<OrderBook>()
    public let ticks = BroadcastHub<Tick>()
    public let orders = BroadcastHub<Order>()
    public let trades = BroadcastHub<Trade>()
    public let snapshots = BroadcastHub<AccountSnapshot>()
    public let positions = BroadcastHub<[Position]>()

    public init() {}
}

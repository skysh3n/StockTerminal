import Foundation

/// 单标的实时价格随机游走（几何布朗运动 + 波动率聚集 + 涨跌停约束）。
public struct RandomWalk: Sendable {
    public var price: Decimal
    public let preClose: Decimal
    public let upperLimit: Decimal
    public let lowerLimit: Decimal
    public let tick: Decimal
    /// 当前每 tick 波动率（均值回归的 regime 变量，制造活跃/清淡行情）
    public var regime: Double
    public let baseVol: Double
    /// 当前漂移（缓慢游走，制造趋势与反转）
    public var drift: Double

    public init(price: Decimal, preClose: Decimal, upperLimit: Decimal, lowerLimit: Decimal, tick: Decimal, baseVol: Double = 0.0002) {
        self.price = price
        self.preClose = preClose
        self.upperLimit = upperLimit
        self.lowerLimit = lowerLimit
        self.tick = tick
        self.baseVol = baseVol
        self.regime = baseVol
        self.drift = 0
    }

    /// 推进一步，返回新价格（已按 tick 取整并夹在涨跌停内）
    @discardableResult
    public mutating func step(rng: inout SplitMix64) -> Decimal {
        // 波动率聚集：均值回归 + 噪声，偶发放量活跃
        regime += (baseVol - regime) * 0.02 + rng.gaussian() * baseVol * 0.12
        regime = min(max(regime, baseVol * 0.25), baseVol * 4)
        // 漂移缓慢游走
        drift += rng.gaussian() * 0.000_02
        drift = min(max(drift, -0.0004), 0.0004)

        let ret = drift + regime * rng.gaussian()
        var p = (price * Decimal(1 + ret)).quantized(to: tick)
        p = min(max(p, lowerLimit), upperLimit)
        price = p
        return p
    }
}

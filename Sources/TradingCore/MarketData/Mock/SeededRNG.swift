import Foundation

/// SplitMix64：快速、可复现的伪随机数发生器（种子相同 → 序列相同）。
/// 用于所有 Mock 数据生成，保证同一次运行行情走势可复现，便于测试与演示。
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// [0, 1) 均匀分布
    public mutating func unitDouble() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    /// 标准正态分布（Box-Muller）
    public mutating func gaussian() -> Double {
        let u1 = max(unitDouble(), 1e-12)
        let u2 = unitDouble()
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }

    /// [lo, hi) 均匀分布
    public mutating func range(_ lo: Double, _ hi: Double) -> Double {
        lo + unitDouble() * (hi - lo)
    }
}

/// FNV-1a 64位字符串哈希（String.hashValue 每进程加盐，不可用于跨运行种子派生）
public func fnv1a64(_ s: String) -> UInt64 {
    var h: UInt64 = 0xcbf2_9ce4_8422_2325
    for b in s.utf8 {
        h ^= UInt64(b)
        h = h &* 0x0000_0100_0000_01b3
    }
    return h
}

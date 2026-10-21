import XCTest
@testable import TradingCore

final class SeededRNGTests: XCTestCase {
    func testSameSeedSameSequence() {
        var a = SplitMix64(seed: 42)
        var b = SplitMix64(seed: 42)
        for _ in 0..<100 {
            XCTAssertEqual(a.next(), b.next())
        }
    }

    func testDifferentSeedDifferentSequence() {
        var a = SplitMix64(seed: 1)
        var b = SplitMix64(seed: 2)
        XCTAssertNotEqual(a.next(), b.next())
    }

    func testUnitDoubleInRange() {
        var rng = SplitMix64(seed: 7)
        for _ in 0..<1000 {
            let v = rng.unitDouble()
            XCTAssertGreaterThanOrEqual(v, 0)
            XCTAssertLessThan(v, 1)
        }
    }

    func testGaussianRoughlyStandardNormal() {
        var rng = SplitMix64(seed: 99)
        var sum = 0.0, sumSq = 0.0
        let n = 20000
        for _ in 0..<n {
            let g = rng.gaussian()
            sum += g
            sumSq += g * g
        }
        let mean = sum / Double(n)
        let variance = sumSq / Double(n) - mean * mean
        XCTAssertLessThan(abs(mean), 0.05, "均值应接近 0")
        XCTAssertLessThan(abs(variance - 1), 0.1, "方差应接近 1")
    }
}

final class DecimalMoneyTests: XCTestCase {
    func testQuantizedToTick() {
        let tick = Decimal(string: "0.01")!
        XCTAssertEqual(Decimal(string: "10.126")!.quantized(to: tick), Decimal(string: "10.13")!)
        XCTAssertEqual(Decimal(string: "10.124")!.quantized(to: tick), Decimal(string: "10.12")!)
        XCTAssertEqual(Decimal(string: "10.125")!.quantized(to: tick), Decimal(string: "10.13")!) // away from zero
    }

    func testDoubleValue() {
        XCTAssertEqual(Decimal(string: "3.14")!.doubleValue, 3.14, accuracy: 1e-9)
    }
}

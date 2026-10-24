import Foundation

/// 东财个股资金流（fflow kline 尾部汇总）。
public struct EastmoneyFundFlowClient: Sendable {
    private let session: URLSession

    public init() {
        session = EastmoneyHTTP.makeSession(referer: "https://data.eastmoney.com/")
    }

    public func snapshot(fullCode: String) async throws -> FundFlowSnapshot? {
        guard fullCode.count == 8,
              let market = marketID(fullCode: fullCode)
        else { return nil }
        let code = String(fullCode.suffix(6))
        let hosts = EastmoneyHTTP.clistHosts
        var lastError: Error = ServiceError.backend("资金流不可用")
        for host in hosts {
            let urlString =
                "\(host)/api/qt/stock/fflow/kline/get?lmt=0&klt=1&secid=\(market).\(code)&fields1=f1,f2,f3,f7&fields2=f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61,f62,f63,f64,f65"
            guard let url = URL(string: urlString) else { continue }
            do {
                let (data, _) = try await session.data(from: url)
                if data.isEmpty { continue }
                if let snap = try Self.parse(data: data, symbol: fullCode) {
                    return snap
                }
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// kline 行：`时间,主力净流入,小单净流入,中单,大单,超大单,...`（东财常见顺序）。
    public static func parse(data: Data, symbol: String) throws -> FundFlowSnapshot? {
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dataObj = json["data"] as? [String: Any],
            let lines = dataObj["klines"] as? [String],
            let last = lines.last
        else { return nil }
        let parts = last.split(separator: ",").map(String.init)
        guard parts.count >= 3 else { return nil }
        let main = Decimal(string: parts[1]) ?? 0
        let retail = Decimal(string: parts[2]) ?? 0
        return FundFlowSnapshot(
            symbol: symbol,
            mainNetInflow: main,
            retailNetInflow: retail,
            asOf: Date()
        )
    }

    private func marketID(fullCode: String) -> Int? {
        switch String(fullCode.prefix(2)) {
        case "SH": return 1
        case "SZ": return 0
        case "BJ": return 0
        default: return nil
        }
    }
}

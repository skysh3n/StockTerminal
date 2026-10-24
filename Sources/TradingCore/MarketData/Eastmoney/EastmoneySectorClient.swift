import Foundation

/// 东财行业 / 概念板块榜 + 成分股（clist）。失败时由上层回退新浪。
public struct EastmoneySectorClient: Sendable {
    private let session: URLSession

    public init() {
        session = EastmoneyHTTP.makeSession(referer: "https://quote.eastmoney.com/")
    }

    public func sectors(kind: SectorKind, limit: Int = 40) async throws -> [SectorBoard] {
        let fs: String = {
            switch kind {
            case .industry: return "m:90+t:2+f:!50"
            case .concept: return "m:90+t:3+f:!50"
            }
        }()
        let pz = min(max(limit, 1), 50)
        let fields = "f12,f14,f2,f3,f104,f105,f128,f136"
        let query =
            "pn=1&pz=\(pz)&po=1&np=1&fltt=2&invt=2&fid=f3&fs=\(fs)&fields=\(fields)"
        let data = try await EastmoneyHTTP.fetchClist(session: session, query: query)
        return try Self.parseSectors(data: data, limit: pz)
    }

    public func constituents(boardCode: String, limit: Int = 40) async throws -> [MarketRankItem] {
        let code = boardCode.hasPrefix("BK") ? boardCode : boardCode
        let pz = min(max(limit, 1), 50)
        let fields = "f12,f13,f14,f2,f3,f4,f5,f6"
        let query =
            "pn=1&pz=\(pz)&po=1&np=1&fltt=2&invt=2&fid=f3&fs=b:\(code)+f:!50&fields=\(fields)"
        let data = try await EastmoneyHTTP.fetchClist(session: session, query: query)
        return try EastmoneyRankClient.parse(data: data, limit: pz)
    }

    public static func parseSectors(data: Data, limit: Int) throws -> [SectorBoard] {
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dataObj = json["data"] as? [String: Any],
            let rows = dataObj["diff"] as? [[String: Any]]
        else {
            throw ServiceError.backend("板块榜解析失败")
        }
        var out: [SectorBoard] = []
        for row in rows {
            guard let code = stringValue(row["f12"]), !code.isEmpty,
                  let name = stringValue(row["f14"]), !name.isEmpty
            else { continue }
            out.append(SectorBoard(
                code: code,
                name: name,
                changePercent: doubleValue(row["f3"]),
                upCount: intValue(row["f104"]) ?? 0,
                downCount: intValue(row["f105"]) ?? 0,
                leadName: stringValue(row["f128"]) ?? "",
                leadChangePercent: doubleValue(row["f136"]),
                sourceNode: code
            ))
            if out.count >= limit { break }
        }
        return out
    }

    private static func stringValue(_ any: Any?) -> String? {
        if let s = any as? String { return s }
        if let n = any as? NSNumber { return n.stringValue }
        return nil
    }

    private static func intValue(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let n = any as? NSNumber { return n.intValue }
        if let s = any as? String { return Int(s) }
        return nil
    }

    private static func doubleValue(_ any: Any?) -> Double {
        if let d = any as? Double { return d }
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String { return Double(s) ?? 0 }
        return 0
    }
}

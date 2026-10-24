import Foundation

/// 新浪行业 / 概念板块（东财 push2 不可用时的公开兜底）。
public struct SinaSectorClient: Sendable {
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            "Referer": "https://finance.sina.com.cn/",
        ]
        session = URLSession(configuration: config)
    }

    public func industrySectors(limit: Int = 40) async throws -> [SectorBoard] {
        guard let url = URL(string: "https://vip.stock.finance.sina.com.cn/q/view/newSinaHy.php") else {
            return []
        }
        let (data, _) = try await session.data(from: url)
        return try Self.parseIndustry(data: data, limit: limit)
    }

    /// 概念：从行情中心节点树取「热门概念」前若干，再并发拉涨跌幅。
    public func conceptSectors(limit: Int = 30) async throws -> [SectorBoard] {
        let nodes = Array((try await hotConceptNodes(limit: max(limit, 20))).prefix(limit))
        return try await withThrowingTaskGroup(of: SectorBoard?.self) { group in
            for node in nodes {
                group.addTask {
                    try? await self.conceptSnapshot(name: node.name, node: node.code)
                }
            }
            var boards: [SectorBoard] = []
            for try await board in group {
                if let board { boards.append(board) }
            }
            boards.sort { $0.changePercent > $1.changePercent }
            return boards
        }
    }

    public func constituents(node: String, limit: Int = 40) async throws -> [MarketRankItem] {
        let encoded = node.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? node
        let urlString =
            "https://vip.stock.finance.sina.com.cn/quotes_service/api/json_v2.php/Market_Center.getHQNodeData?page=1&num=\(min(max(limit, 1), 80))&sort=changepercent&asc=0&node=\(encoded)"
        guard let url = URL(string: urlString) else { return [] }
        let (data, _) = try await session.data(from: url)
        return try Self.parseConstituents(data: data, limit: limit)
    }

    // MARK: - Parse

    public static func parseIndustry(data: Data, limit: Int) throws -> [SectorBoard] {
        let text = String(data: data, encoding: .utf8)
            ?? GB18030.decode(data)
            ?? ""
        guard let brace = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              let jsonData = String(text[brace...end]).data(using: .utf8),
              let dict = try JSONSerialization.jsonObject(with: jsonData) as? [String: String]
        else {
            throw ServiceError.backend("新浪行业解析失败")
        }
        var out: [SectorBoard] = []
        for (_, raw) in dict {
            let p = raw.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard p.count >= 13 else { continue }
            let code = p[0]
            let name = p[1]
            let pct = Double(p[5]) ?? 0
            let leadCode = p[8]
            let leadPct = Double(p[9]) ?? 0
            let leadName = p[12]
            out.append(SectorBoard(
                code: code,
                name: name,
                changePercent: pct,
                upCount: 0,
                downCount: 0,
                leadName: leadName.isEmpty ? leadCode : leadName,
                leadChangePercent: leadPct,
                sourceNode: code
            ))
        }
        out.sort { $0.changePercent > $1.changePercent }
        return Array(out.prefix(limit))
    }

    public static func parseConstituents(data: Data, limit: Int) throws -> [MarketRankItem] {
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ServiceError.backend("成分股解析失败")
        }
        var out: [MarketRankItem] = []
        for row in rows {
            guard let code = row["code"] as? String, code.count == 6,
                  let name = row["name"] as? String,
                  let exchange = RealMarketDataService.exchange(forCode: code)
            else { continue }
            let price = Decimal(string: "\(row["trade"] ?? "0")") ?? 0
            guard price > 0 else { continue }
            let pct = (row["changepercent"] as? Double)
                ?? Double("\(row["changepercent"] ?? "0")")
                ?? 0
            let change = Decimal(string: "\(row["pricechange"] ?? "0")") ?? 0
            let vol = Int64((row["volume"] as? Int) ?? Int("\(row["volume"] ?? "0")") ?? 0)
            let amount = Decimal(string: "\(row["amount"] ?? "0")") ?? 0
            out.append(MarketRankItem(
                symbol: Symbol(code: code, exchange: exchange, name: name),
                lastPrice: price,
                changePercent: pct,
                change: change,
                volumeLots: vol / 100,
                turnover: amount
            ))
            if out.count >= limit { break }
        }
        return out
    }

    private struct ConceptNode { let name: String; let code: String }

    private func hotConceptNodes(limit: Int) async throws -> [ConceptNode] {
        guard let url = URL(string: "https://vip.stock.finance.sina.com.cn/quotes_service/api/json_v2.php/Market_Center.getHQNodes") else {
            return []
        }
        let (data, _) = try await session.data(from: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
        var hot: [ConceptNode] = []
        var all: [ConceptNode] = []
        Self.collectConcepts(root, path: [], hot: &hot, all: &all)
        let preferred = hot.isEmpty ? all : hot
        return Array(preferred.prefix(limit))
    }

    private static func collectConcepts(
        _ node: Any,
        path: [String],
        hot: inout [ConceptNode],
        all: inout [ConceptNode]
    ) {
        guard let arr = node as? [Any] else { return }
        // leaf: [name, "", code]
        if arr.count == 3,
           let name = arr[0] as? String,
           let code = arr[2] as? String,
           !code.isEmpty,
           !(arr[1] is [Any]) {
            let item = ConceptNode(name: name, code: code)
            if path.contains("热门概念") || code.hasPrefix("chgn_") {
                hot.append(item)
            }
            if path.contains("概念板块") || code.hasPrefix("gn_") || code.hasPrefix("chgn_") {
                all.append(item)
            }
            return
        }
        if arr.count >= 2, let title = arr[0] as? String, let children = arr[1] as? [Any] {
            for c in children {
                collectConcepts(c, path: path + [title], hot: &hot, all: &all)
            }
            return
        }
        for c in arr {
            collectConcepts(c, path: path, hot: &hot, all: &all)
        }
    }

    private func conceptSnapshot(name: String, node: String) async throws -> SectorBoard? {
        let items = try await constituents(node: node, limit: 40)
        guard !items.isEmpty else { return nil }
        let avg = items.map(\.changePercent).reduce(0, +) / Double(items.count)
        let up = items.filter { $0.changePercent > 0 }.count
        let down = items.filter { $0.changePercent < 0 }.count
        let lead = items.max(by: { $0.changePercent < $1.changePercent })
        return SectorBoard(
            code: node,
            name: name,
            changePercent: avg,
            upCount: up,
            downCount: down,
            leadName: lead?.symbol.name ?? "",
            leadChangePercent: lead?.changePercent ?? 0,
            sourceNode: node
        )
    }
}

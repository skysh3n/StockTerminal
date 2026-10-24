import Foundation

/// 东方财富个股公告列表（公开接口，正文走外链）。
public struct EastmoneyNoticeClient: Sendable {
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
            "Referer": "https://data.eastmoney.com/",
        ]
        session = URLSession(configuration: config)
    }

    public func notices(code: String, limit: Int = 20) async throws -> [StockNotice] {
        let bare = code.count == 8 ? String(code.suffix(6)) : code
        guard bare.count == 6, bare.allSatisfy(\.isNumber) else { return [] }
        let pageSize = min(max(limit, 1), 50)
        let urlString =
            "https://np-anotice-stock.eastmoney.com/api/security/ann?sr=-1&page_size=\(pageSize)&page_index=1&ann_type=A&stock_list=\(bare)&client_source=web&f_node=0"
        guard let url = URL(string: urlString) else { return [] }
        let (data, _) = try await session.data(from: url)
        return try Self.parse(data: data, code: bare, limit: pageSize)
    }

    public static func parse(data: Data, code: String, limit: Int) throws -> [StockNotice] {
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dataObj = json["data"] as? [String: Any],
            let rows = dataObj["list"] as? [[String: Any]]
        else {
            throw ServiceError.backend("公告解析失败")
        }

        var out: [StockNotice] = []
        for row in rows {
            let art = (row["art_code"] as? String) ?? ""
            let title = (row["title_ch"] as? String)
                ?? (row["title"] as? String)
                ?? "公司公告"
            let date = (row["notice_date"] as? String) ?? ""
            let url: URL? = art.isEmpty
                ? nil
                : URL(string: "https://data.eastmoney.com/notices/detail/\(code)/\(art).html")
            out.append(StockNotice(
                artCode: art,
                symbol: code,
                title: title,
                noticeDate: String(date.prefix(10)),
                url: url
            ))
            if out.count >= limit { break }
        }
        return out
    }
}

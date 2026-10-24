import Foundation

/// 东财资讯标题流（专栏列表，外链打开正文）。
public struct EastmoneyNewsClient: Sendable {
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            "Referer": "https://finance.eastmoney.com/",
        ]
        session = URLSession(configuration: config)
    }

    /// column=350：财经导读类栏目（公开 listapi）。
    public func headlines(limit: Int = 30, column: Int = 350) async throws -> [NewsHeadline] {
        let pageSize = min(max(limit, 1), 50)
        let urlString =
            "https://np-listapi.eastmoney.com/comm/web/getNewsByColumns?client=web&biz=web_news_col&column=\(column)&order=1&needInteractData=0&page_index=1&page_size=\(pageSize)&req_trace=1&fields=code,showTime,title,mediaName,summary,url"
        guard let url = URL(string: urlString) else { return [] }
        let (data, _) = try await session.data(from: url)
        return try Self.parse(data: data, limit: pageSize)
    }

    public static func parse(data: Data, limit: Int) throws -> [NewsHeadline] {
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dataObj = json["data"] as? [String: Any],
            let rows = dataObj["list"] as? [[String: Any]]
        else {
            throw ServiceError.backend("资讯解析失败")
        }
        var out: [NewsHeadline] = []
        for row in rows {
            let code = (row["code"] as? String) ?? ""
            let title = (row["title"] as? String) ?? ""
            guard !title.isEmpty else { continue }
            let media = (row["mediaName"] as? String) ?? ""
            let time = (row["showTime"] as? String) ?? ""
            let summary = (row["summary"] as? String) ?? ""
            let urlStr = (row["url"] as? String) ?? ""
            let url = URL(string: urlStr.hasPrefix("http") ? urlStr : "https:\(urlStr)")
            out.append(NewsHeadline(
                code: code,
                title: title,
                mediaName: media,
                showTime: time,
                summary: summary,
                url: url
            ))
            if out.count >= limit { break }
        }
        return out
    }
}

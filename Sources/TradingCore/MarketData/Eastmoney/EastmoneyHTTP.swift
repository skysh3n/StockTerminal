import Foundation

/// 东财 push2 偶发空响应：多 host + HTTP/1.1 重试。
enum EastmoneyHTTP {
    static let clistHosts = [
        "https://push2.eastmoney.com",
        "https://push2delay.eastmoney.com",
        "https://17.push2.eastmoney.com",
        "https://82.push2.eastmoney.com",
    ]

    static func makeSession(referer: String) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
            "Referer": referer,
            "Accept": "*/*",
        ]
        // 强制 HTTP/1.1，避免部分环境下 h2 空响应
        config.httpAdditionalHeaders?["Connection"] = "close"
        return URLSession(configuration: config)
    }

    static func fetchClist(
        session: URLSession,
        query: String
    ) async throws -> Data {
        var lastError: Error = ServiceError.backend("东财 clist 不可用")
        for host in clistHosts {
            guard let url = URL(string: "\(host)/api/qt/clist/get?\(query)") else { continue }
            do {
                let (data, response) = try await session.data(from: url)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    lastError = ServiceError.backend("HTTP \(http.statusCode)")
                    continue
                }
                if data.isEmpty {
                    lastError = ServiceError.backend("空响应")
                    continue
                }
                return data
            } catch {
                lastError = error
            }
        }
        throw lastError
    }
}

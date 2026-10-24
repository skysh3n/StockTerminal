import Foundation

/// 行业 / 概念板块快照（榜单行）。
public struct SectorBoard: Sendable, Hashable, Identifiable {
    public var id: String { code }
    public let code: String          // 东财 BKxxxx 或新浪 new_xxx / gn_xxx
    public let name: String
    public let changePercent: Double
    public let upCount: Int
    public let downCount: Int
    public let leadName: String
    public let leadChangePercent: Double
    public let sourceNode: String    // 成分股拉取用的节点/板块码

    public init(
        code: String,
        name: String,
        changePercent: Double,
        upCount: Int = 0,
        downCount: Int = 0,
        leadName: String = "",
        leadChangePercent: Double = 0,
        sourceNode: String? = nil
    ) {
        self.code = code
        self.name = name
        self.changePercent = changePercent
        self.upCount = upCount
        self.downCount = downCount
        self.leadName = leadName
        self.leadChangePercent = leadChangePercent
        self.sourceNode = sourceNode ?? code
    }
}

public enum SectorKind: String, Sendable, CaseIterable, Identifiable {
    case industry
    case concept

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .industry: return "行业"
        case .concept: return "概念"
        }
    }
}

/// 资讯标题条目（外链打开）。
public struct NewsHeadline: Sendable, Hashable, Identifiable {
    public var id: String { code.isEmpty ? "\(title)-\(showTime)" : code }
    public let code: String
    public let title: String
    public let mediaName: String
    public let showTime: String
    public let summary: String
    public let url: URL?

    public init(
        code: String,
        title: String,
        mediaName: String,
        showTime: String,
        summary: String,
        url: URL?
    ) {
        self.code = code
        self.title = title
        self.mediaName = mediaName
        self.showTime = showTime
        self.summary = summary
        self.url = url
    }
}

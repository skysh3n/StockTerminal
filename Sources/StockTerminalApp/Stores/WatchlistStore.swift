import Foundation
import Observation
import TradingCore

/// 用户自定义板块。`system` 为内置「自选」，不可删除。
struct WatchBoard: Identifiable, Hashable {
    var id: UUID
    var name: String
    var system: Bool
    var codes: [String]
}

/// 自选列表排序。
enum WatchlistSort: String, CaseIterable {
    case manual
    case changeDesc
    case changeAsc
    case priceDesc

    var label: String {
        switch self {
        case .manual: return "默认"
        case .changeDesc: return "涨幅↓"
        case .changeAsc: return "涨幅↑"
        case .priceDesc: return "现价↓"
        }
    }
}

/// 自选与自定义板块、当前标的/周期、搜索词。
/// 持久化到 Application Support/StockTerminal/boards.json。
/// 旧版 watchlist.json 会在首次启动时迁入「自选」。
/// 市场榜单不在此 Store —— 见「榜单」工作区 / MarketBoardStore。
@MainActor
@Observable
final class WatchlistStore {
    private(set) var boards: [WatchBoard] = []
    private(set) var activeBoardID = UUID()

    var selectedCode: String?
    var selectedTimeFrame: TimeFrame = .day
    var query: String = ""
    var sort: WatchlistSort = .manual

    let universeInitial: [Symbol]
    private(set) var universe: [Symbol]
    private var universeMap: [String: Symbol]

    var activeBoard: WatchBoard? { boards.first { $0.id == activeBoardID } }

    /// 当前板块里的代码（未排序）。
    var codes: [String] { activeBoard?.codes ?? [] }

    /// 按当前排序规则返回代码（需传入现价回调）。
    func sortedCodes(quote: (String) -> Quote?) -> [String] {
        let base = codes
        switch sort {
        case .manual:
            return base
        case .changeDesc:
            return base.sorted { (quote($0)?.changePercent ?? -999) > (quote($1)?.changePercent ?? -999) }
        case .changeAsc:
            return base.sorted { (quote($0)?.changePercent ?? 999) < (quote($1)?.changePercent ?? 999) }
        case .priceDesc:
            return base.sorted { (quote($0)?.lastPrice ?? 0) > (quote($1)?.lastPrice ?? 0) }
        }
    }

    init(universe: [Symbol], defaultWatchlist: [String] = []) {
        self.universeInitial = universe
        var pool = universe
        var map = Dictionary(uniqueKeysWithValues: universe.map { ($0.fullCode, $0) })

        func absorb(_ item: PersistedStock) {
            let full = item.fullCode
            guard map[full] == nil else { return }
            guard let exchange = Exchange(rawValue: item.exchange),
                  item.code.count == 6, item.code.allSatisfy(\.isNumber) else { return }
            let symbol = Symbol(code: item.code, exchange: exchange, name: item.name)
            map[full] = symbol
            pool.append(symbol)
        }

        let boards: [WatchBoard]
        let activeID: UUID
        var dirty = false

        if let restored = Self.loadLibrary() {
            for item in restored.symbols { absorb(item) }
            var loaded: [WatchBoard] = []
            for item in restored.boards {
                var unique: [String] = []
                for code in item.codes where map[code] != nil && !unique.contains(code) {
                    unique.append(code)
                }
                loaded.append(WatchBoard(id: item.id, name: item.name, system: item.system, codes: unique))
            }
            if loaded.isEmpty {
                loaded = [WatchBoard(id: UUID(), name: "自选", system: true, codes: [])]
                dirty = true
            } else if !loaded.contains(where: \.system) {
                loaded.insert(WatchBoard(id: UUID(), name: "自选", system: true, codes: []), at: 0)
                dirty = true
            }
            boards = loaded
            activeID = loaded.contains(where: { $0.id == restored.activeID }) ? restored.activeID : loaded[0].id
        } else {
            var seeded: [String] = []
            if let legacy = Self.loadLegacyStocks() {
                for item in legacy { absorb(item) }
                for item in legacy where map[item.fullCode] != nil && !seeded.contains(item.fullCode) {
                    seeded.append(item.fullCode)
                }
            }
            if seeded.isEmpty {
                seeded = defaultWatchlist.filter { map[$0] != nil }
            }
            if seeded.isEmpty {
                seeded = Array(universe.prefix(12).map(\.fullCode))
            }
            let home = WatchBoard(id: UUID(), name: "自选", system: true, codes: seeded)
            boards = [home]
            activeID = home.id
            dirty = true
        }

        self.universe = pool
        self.universeMap = map
        self.boards = boards
        self.activeBoardID = activeID
        self.selectedCode = boards.first { $0.id == activeID }?.codes.first
        if dirty { persist() }
    }

    func symbol(for code: String) -> Symbol? { universeMap[code] }

    func contains(_ code: String) -> Bool { codes.contains(code) }

    func register(_ symbol: Symbol) {
        guard universeMap[symbol.fullCode] == nil else { return }
        universeMap[symbol.fullCode] = symbol
        universe.append(symbol)
    }

    func add(_ code: String) {
        add(code, to: activeBoardID)
    }

    func add(_ code: String, to boardID: UUID) {
        guard universeMap[code] != nil, let index = boards.firstIndex(where: { $0.id == boardID }) else { return }
        guard !boards[index].codes.contains(code) else { return }
        boards[index].codes.append(code)
        persist()
    }

    func remove(_ code: String) {
        guard let index = boards.firstIndex(where: { $0.id == activeBoardID }) else { return }
        boards[index].codes.removeAll { $0 == code }
        if selectedCode == code { selectedCode = codes.first }
        persist()
    }

    func select(_ code: String) {
        guard universeMap[code] != nil else { return }
        selectedCode = code
    }

    @discardableResult
    func createBoard(name: String) -> UUID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 12, boards.count < 16 else { return nil }
        guard !boards.contains(where: { $0.name == trimmed }) else { return nil }
        let board = WatchBoard(id: UUID(), name: trimmed, system: false, codes: [])
        boards.append(board)
        activeBoardID = board.id
        persist()
        return board.id
    }

    func renameBoard(_ id: UUID, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 12 else { return }
        guard !boards.contains(where: { $0.id != id && $0.name == trimmed }) else { return }
        guard let index = boards.firstIndex(where: { $0.id == id }), !boards[index].system else { return }
        boards[index].name = trimmed
        persist()
    }

    /// 删除自定义板块。若删的是当前板块，回到「自选」。
    func deleteBoard(_ id: UUID) {
        guard let board = boards.first(where: { $0.id == id }), !board.system else { return }
        boards.removeAll { $0.id == id }
        if activeBoardID == id {
            activeBoardID = boards.first(where: \.system)?.id ?? boards[0].id
            if selectedCode.map({ !codes.contains($0) }) ?? true {
                selectedCode = codes.first
            }
        }
        persist()
    }

    /// 切换板块。当前股票不在新板块里时，选中该板块第一只。
    func activate(_ id: UUID) {
        guard id != activeBoardID, boards.contains(where: { $0.id == id }) else { return }
        activeBoardID = id
        if let selectedCode, codes.contains(selectedCode) { return }
        if let first = codes.first { self.selectedCode = first }
        persist()
    }

    // MARK: - 持久化

    private struct PersistedStock: Codable {
        let code: String
        let name: String
        let exchange: String
        var fullCode: String { exchange + code }
    }

    private struct PersistedBoard: Codable {
        var id: UUID
        var name: String
        var system: Bool
        var codes: [String]
    }

    private struct PersistedLibrary: Codable {
        var activeID: UUID
        var boards: [PersistedBoard]
        var symbols: [PersistedStock]
    }

    private static var supportDir: URL? {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent("StockTerminal", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var libraryURL: URL? {
        supportDir?.appendingPathComponent("boards.json")
    }

    private static var legacyURL: URL? {
        supportDir?.appendingPathComponent("watchlist.json")
    }

    private static func loadLibrary() -> PersistedLibrary? {
        guard let url = libraryURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PersistedLibrary.self, from: data)
    }

    private static func loadLegacyStocks() -> [PersistedStock]? {
        guard let url = legacyURL, let data = try? Data(contentsOf: url) else { return nil }
        let saved = try? JSONDecoder().decode([PersistedStock].self, from: data)
        guard let saved, !saved.isEmpty else { return nil }
        return saved
    }

    private func persist() {
        guard let url = Self.libraryURL else { return }
        let referenced = Set(boards.flatMap(\.codes))
        let symbols = referenced.compactMap { universeMap[$0] }.map {
            PersistedStock(code: $0.code, name: $0.name, exchange: $0.exchange.rawValue)
        }
        let library = PersistedLibrary(
            activeID: activeBoardID,
            boards: boards.map {
                PersistedBoard(id: $0.id, name: $0.name, system: $0.system, codes: $0.codes)
            },
            symbols: symbols
        )
        guard let data = try? JSONEncoder().encode(library) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

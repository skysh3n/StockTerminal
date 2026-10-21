import Foundation

/// 账户服务协议（跨平台预留的核心边界之一）。
public protocol AccountService: Sendable {
    /// 资产快照
    func snapshot() async throws -> AccountSnapshot

    /// 当前持仓
    func positions() async throws -> [Position]

    /// 资产变化推送
    func subscribeSnapshot() -> AsyncStream<AccountSnapshot>

    /// 持仓变化推送
    func subscribePositions() -> AsyncStream<[Position]>
}

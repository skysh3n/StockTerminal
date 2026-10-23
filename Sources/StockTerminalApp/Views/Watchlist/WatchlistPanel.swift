import SwiftUI
import DesignSystem
import TradingCore

/// 左栏：自选股列表（实时跳动 + 行内缩浮层 hover + 价格闪烁 + 右键删除）
struct WatchlistPanel: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showCreate = false
    @State private var newName = ""
    @State private var renameTarget: WatchBoard?
    @State private var renameText = ""

    var body: some View {
        @Bindable var wl = env.watchlist
        VStack(spacing: 0) {
            PanelHeader(wl.activeBoard?.name ?? "自选") {
                Tag(text: "\(wl.codes.count)", color: .dsTextSecondary)
            }
            boardStrip
            Rectangle().fill(Color.dsBorder.opacity(0.7)).frame(height: 0.5)

            // 列头
            HStack(spacing: 6) {
                Text("代码 / 名称").tracking(0.3)
                Spacer(minLength: 2)
                Text("现价").tracking(0.3).frame(width: 66, alignment: .trailing)
                Text("涨跌幅").tracking(0.3).frame(width: 62, alignment: .trailing)
            }
            .font(.dsMicro())
            .foregroundStyle(Color.dsTextTertiary)
            .padding(.horizontal, 14)
            .padding(.vertical, 4)

            if wl.codes.isEmpty {
                Spacer(minLength: 0)
                VStack(spacing: 6) {
                    Text("这个板块还没有股票")
                        .font(.dsFootnote(medium: true))
                        .foregroundStyle(Color.dsTextSecondary)
                    Text("搜索代码或名称，回车加入当前板块")
                        .font(.dsMicro())
                        .foregroundStyle(Color.dsTextTertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 18)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(wl.codes, id: \.self) { code in
                            if let state = env.market.states[code] {
                                WatchlistRow(state: state, selected: wl.selectedCode == code)
                                    .padding(.horizontal, 6)
                                    .contentShape(Rectangle())
                                    .onTapGesture { wl.select(code) }
                                    .contextMenu { rowMenu(code: code, boards: wl.boards) }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .popover(isPresented: $showCreate, arrowEdge: .bottom) { namePopover(creating: true) }
        .alert("重命名板块", isPresented: renamePresented) {
            TextField("名称", text: $renameText)
            Button("取消", role: .cancel) {}
            Button("确定") {
                if let renameTarget { env.watchlist.renameBoard(renameTarget.id, name: renameText) }
            }
        } message: {
            Text("最多 12 个字，不能和已有板块重名。")
        }
    }

    private var renamePresented: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
    }

    private var boardStrip: some View {
        let wl = env.watchlist
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(wl.boards) { board in
                    boardChip(board, active: board.id == wl.activeBoardID)
                }
                Button {
                    newName = ""
                    showCreate = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.dsTextSecondary)
                        .frame(width: 22, height: 22)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.dsElevated.opacity(0.8)))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.dsBorder, lineWidth: 0.6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("新建板块")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    private func boardChip(_ board: WatchBoard, active: Bool) -> some View {
        Button {
            env.showBoard(board.id)
        } label: {
            Text(board.name)
                .font(.dsMicro(medium: active))
                .lineLimit(1)
                .foregroundStyle(active ? Color.dsTextPrimary : Color.dsTextTertiary)
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(active ? Color.dsAccent.opacity(0.16) : Color.dsElevated.opacity(0.45))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(active ? Color.dsAccent.opacity(0.45) : Color.dsBorder, lineWidth: 0.6)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !board.system {
                Button("重命名") {
                    renameText = board.name
                    renameTarget = board
                }
                Button("删除板块", role: .destructive) { env.removeBoard(board.id) }
            }
        }
    }

    @ViewBuilder
    private func rowMenu(code: String, boards: [WatchBoard]) -> some View {
        let others = boards.filter { $0.id != env.watchlist.activeBoardID }
        if !others.isEmpty {
            Menu("加入板块") {
                ForEach(others) { board in
                    Button(board.name) {
                        if let symbol = env.watchlist.symbol(for: code) {
                            env.watchlist.register(symbol)
                        }
                        env.watchlist.add(code, to: board.id)
                    }
                }
            }
        }
        Button("移出本板块", role: .destructive) { env.watchlist.remove(code) }
    }

    private func namePopover(creating: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(creating ? "新建板块" : "重命名")
                .font(.dsMicro(medium: true))
                .foregroundStyle(Color.dsTextTertiary)
            TextField("例如 科技", text: $newName)
                .textFieldStyle(.plain)
                .font(.dsFootnote())
                .foregroundStyle(Color.dsTextPrimary)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .inputBox(focused: true)
                .onSubmit { commitCreate() }
            HStack {
                Spacer()
                Button("创建") { commitCreate() }
                    .buttonStyle(.plain)
                    .font(.dsMicro(medium: true))
                    .foregroundStyle(newName.trimmingCharacters(in: .whitespaces).isEmpty ? Color.dsTextTertiary : Color.dsAccent)
            }
        }
        .padding(12)
        .frame(width: 196)
        .background(Color.dsPanel)
    }

    private func commitCreate() {
        guard env.watchlist.createBoard(name: newName) != nil else { return }
        newName = ""
        showCreate = false
    }
}

/// 单行：只读本行 SymbolState 的 quote —— 某只股票跳动只重绘它自己这一行
struct WatchlistRow: View {
    let state: SymbolState
    let selected: Bool

    @State private var flashOpacity: Double = 0
    @State private var flashUp: Bool = true
    @State private var flashTask: Task<Void, Never>?

    var body: some View {
        let q = state.quote
        let changeColor = Sem.change(q?.changePercent)

        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1.5) {
                Text(state.symbol.name)
                    .font(.dsBody(medium: true))
                    .foregroundStyle(Color.dsTextPrimary)
                    .lineLimit(1)
                Text(state.symbol.fullCode)
                    .font(.dsMicro())
                    .tracking(0.2)
                    .foregroundStyle(Color.dsTextTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 1.5) {
                Text(Fmt.price(q?.lastPrice))
                    .font(.dsCallout(medium: true))
                    .tracking(-0.1)
                    .foregroundStyle(changeColor)
                Text(Fmt.signed(q?.change))
                    .font(.dsMicro())
                    .foregroundStyle(changeColor.opacity(0.8))
            }
            .frame(width: 66, alignment: .trailing)

            ChangeChip(text: Fmt.pct(q?.changePercent), color: changeColor, compact: true)
                .frame(width: 62, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(flashBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .rowHover(selected: selected, radius: 6)
        .onChange(of: q?.lastPrice) { old, new in
            guard let o = old, let n = new, o != n else { return }
            flashUp = n > o
            flashOpacity = 0.30
            // 瞬时点亮→熄灭（真实终端的闪烁做法）：每次变动只触发两次重绘，
            // 不用持续动画——避免 12 行 × 4Hz 的隐式动画把渲染循环钉满 60fps
            flashTask?.cancel()
            flashTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                flashOpacity = 0
            }
        }
    }

    private var flashBackground: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill((flashUp ? Sem.up : Sem.down).opacity(flashOpacity))
    }
}

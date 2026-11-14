import SwiftUI
import AkweKit

/// 3.3 Manage pockets — drag categories between pockets, rename, add.
struct ManagePocketsView: View {
    @Environment(AppModel.self) private var app
    @State private var editingPocket: Pocket?
    @State private var newCategoryPocket: Pocket?
    @State private var newName = ""
    @State private var budgetFor: TxCategory?
    @State private var dropTarget: UUID?

    private static let palette = ["#7C9CFF", "#FF9F5A", "#3DDC97", "#C084FC", "#FF7EB6", "#FFB86B", "#12B5A6", "#8B8B96"]
    private static let icons = ["house.fill", "fork.knife", "car.fill", "bag.fill", "heart.fill", "airplane", "gamecontroller.fill", "pawprint.fill", "graduationcap.fill", "gift.fill", "ellipsis"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(tr("pockets.subtitle")).font(.system(size: 15)).foregroundStyle(Palette.text2)

                ForEach(app.pockets.sorted { $0.sort < $1.sort }) { p in
                    pocketCard(p)
                }

                Button {
                    editingPocket = Pocket(id: UUID(), name: "", icon: "ellipsis", color: Self.palette.randomElement()!, sort: (app.pockets.map(\.sort).max() ?? 0) + 1)
                } label: {
                    Label(tr("pockets.new"), systemImage: "plus").font(.system(size: 15, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 52)
                        .background(RoundedRectangle(cornerRadius: 18).strokeBorder(Palette.text.opacity(0.2), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                }
                .buttonStyle(.row)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .background(Palette.ground)
        .navigationTitle(tr("pockets.title"))
        .sheet(item: $editingPocket) { p in PocketEditor(pocket: p, colors: Self.palette, icons: Self.icons) }
        .sheet(item: $budgetFor) { c in BudgetEditor(title: c.name, pocketId: nil, categoryId: c.id, current: app.budgets.first { $0.categoryId == c.id }?.amount) }
        .alert(tr("pockets.newCategory"), isPresented: Binding(get: { newCategoryPocket != nil }, set: { if !$0 { newCategoryPocket = nil } })) {
            TextField(tr("pockets.categoryName"), text: $newName)
            Button(tr("common.add")) {
                if let p = newCategoryPocket, !newName.isEmpty {
                    Task { await app.saveCategory(TxCategory(id: UUID(), pocketId: p.id, name: newName, icon: p.icon, sort: 50)) }
                }
                newName = ""
            }
            Button(tr("common.cancel"), role: .cancel) { newName = "" }
        }
    }

    private func pocketCard(_ p: Pocket) -> some View {
        let cats = app.categories.filter { $0.pocketId == p.id && !$0.archived }.sorted { $0.sort < $1.sort }
        let color = Color(hexString: p.color)
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                IconTile(systemName: p.icon, color: color, size: 34, radius: 12)
                Text(p.name).font(.system(size: 17, weight: .bold))
                Spacer()
                Text(tr("pockets.count", cats.count)).font(.system(size: 13)).foregroundStyle(Palette.text2)
                Menu {
                    Button { editingPocket = p } label: { Label(tr("common.edit"), systemImage: "pencil") }
                    Button { newCategoryPocket = p } label: { Label(tr("pockets.newCategory"), systemImage: "plus") }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 32, height: 32)
                }
                .accessibilityLabel(tr("common.edit"))
            }
            .frame(minHeight: 52)

            ForEach(cats) { c in
                HStack(spacing: 12) {
                    Text(c.name).font(.system(size: 15)).foregroundStyle(Palette.text)
                    Spacer()
                    if let b = app.budgets.first(where: { $0.categoryId == c.id }) {
                        Text(money(b.amount, b.currency, cents: false)).font(.system(size: 13)).foregroundStyle(Palette.text2)
                    }
                    Image(systemName: "line.3.horizontal").foregroundStyle(Palette.text3)
                }
                .padding(.leading, 46)
                .frame(minHeight: 46)
                .contentShape(Rectangle())
                .draggable(c.id.uuidString) {
                    Text(c.name).font(.system(size: 15, weight: .semibold)).padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Palette.raised, in: Capsule())
                }
                .contextMenu {
                    Button { budgetFor = c } label: { Label(tr("budget.set"), systemImage: "gauge.with.dots.needle.33percent") }
                    Menu(tr("pockets.moveTo")) {
                        ForEach(app.pockets.filter { $0.id != p.id }) { other in
                            Button(other.name) { Task { await app.moveCategory(c, to: other) } }
                        }
                    }
                    if c.key == nil {
                        Button(role: .destructive) { var a = c; a.archived = true; Task { await app.saveCategory(a) } } label: { Label(tr("common.delete"), systemImage: "trash") }
                    }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 4)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).stroke(color, lineWidth: dropTarget == p.id ? 2 : 0))
        .scaleEffect(dropTarget == p.id ? 1.02 : 1)
        .animation(Motion.bouncy, value: dropTarget)
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first.flatMap(UUID.init(uuidString:)), let c = app.categories.first(where: { $0.id == id }), c.pocketId != p.id else { return false }
            Task { await app.moveCategory(c, to: p) }
            return true
        } isTargeted: { on in
            if on { dropTarget = p.id; Haptics.selection() } else if dropTarget == p.id { dropTarget = nil }
        }
    }
}

struct PocketEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State var pocket: Pocket
    let colors: [String]
    let icons: [String]

    var body: some View {
        NavigationStack {
            Form {
                TextField(tr("pockets.name"), text: $pocket.name)
                Section(tr("pockets.color")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8)) {
                        ForEach(colors, id: \.self) { c in
                            Circle().fill(Color(hexString: c)).frame(width: 30, height: 30)
                                .overlay(Circle().stroke(Palette.text, lineWidth: pocket.color == c ? 2 : 0).padding(-3))
                                .onTapGesture { pocket.color = c; Haptics.selection() }
                                .accessibilityAddTraits(.isButton)
                        }
                    }
                }
                Section(tr("pockets.icon")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6)) {
                        ForEach(icons, id: \.self) { i in
                            IconTile(systemName: i, color: pocket.icon == i ? Color(hexString: pocket.color) : Palette.text2, size: 40)
                                .onTapGesture { pocket.icon = i; Haptics.selection() }
                                .accessibilityAddTraits(.isButton)
                        }
                    }
                }
            }
            .navigationTitle(pocket.name.isEmpty ? tr("pockets.new") : pocket.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("common.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("common.save")) { Task { await app.savePocket(pocket); dismiss() } }.disabled(pocket.name.isEmpty)
                }
            }
        }
    }
}

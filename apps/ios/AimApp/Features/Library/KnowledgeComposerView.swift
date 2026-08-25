import SwiftUI

/// 手动新增 / 编辑一条知识条目。
///
/// 资料库是积累下来的内容——你和 AIM 都能往里加。这是「你自己加」那条路径。
struct KnowledgeComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: KnowledgeComposerModel
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let editingID: UUID?
    private let store: LibraryStore

    init(store: LibraryStore, category: LibraryCategoryID) {
        self.store = store
        editingID = nil
        _model = State(initialValue: KnowledgeComposerModel(category: category))
    }

    init(store: LibraryStore, entry: KnowledgeEntry) {
        self.store = store
        editingID = entry.id
        _model = State(initialValue: KnowledgeComposerModel(entry: entry))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("记什么") {
                    Picker("形态", selection: $model.form) {
                        Text("菜谱").tag(KnowledgeForm.recipe)
                        Text("能不能吃").tag(KnowledgeForm.foodRule)
                        Text("步骤").tag(KnowledgeForm.howto)
                        Text("提示").tag(KnowledgeForm.tip)
                    }
                    .pickerStyle(.segmented)
                    TextField("标题", text: $model.title)
                        .accessibilityIdentifier("knowledge-title")
                }

                switch model.form {
                case .recipe:
                    editableList("食材", items: $model.ingredients, id: "ingredient")
                    editableList("做法", items: $model.steps, id: "step")
                    // 用途是以后找到这道菜的入口。
                    editableList("用途（可选）", items: $model.purposes, id: "purpose")
                case .foodRule:
                    Section("结论（可选）") {
                        // 「补铁要配维C」这类建议归不进任何一档，所以允许不选。
                        Picker("结论", selection: $model.verdict) {
                            Text("不给结论").tag(FoodVerdict?.none)
                            Text("可以吃").tag(FoodVerdict?.some(.safe))
                            Text("限量").tag(FoodVerdict?.some(.limit))
                            Text("避免").tag(FoodVerdict?.some(.avoid))
                        }
                        .pickerStyle(.segmented)
                        TextField("为什么", text: $model.reason, axis: .vertical)
                            .accessibilityIdentifier("knowledge-reason")
                    }
                case .howto:
                    editableList("步骤", items: $model.steps, id: "step")
                case .tip, .unknown:
                    Section("内容") {
                        TextField("写下要记住的事", text: $model.body, axis: .vertical)
                            .accessibilityIdentifier("knowledge-body")
                    }
                }

                Section("补充（可选）") {
                    TextField("备注", text: $model.note, axis: .vertical)
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(Color.aimDanger) }
                }
            }
            .navigationTitle(editingID == nil ? "新增资料" : "编辑资料")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await save() } }
                        .disabled(!model.canSave || isSaving)
                        .accessibilityIdentifier("knowledge-save")
                }
            }
        }
    }

    /// 可增删的文本行。食材和步骤都是这种形状，一个组件覆盖两处。
    @ViewBuilder
    private func editableList(_ title: String, items: Binding<[String]>, id: String) -> some View {
        Section(title) {
            ForEach(items.indices, id: \.self) { index in
                HStack {
                    TextField("第 \(index + 1) 条", text: items[index], axis: .vertical)
                        .accessibilityIdentifier("knowledge-\(id)-\(index)")
                    if items.wrappedValue.count > 1 {
                        Button {
                            items.wrappedValue.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle").foregroundStyle(Color.aimTextTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Button {
                items.wrappedValue.append("")
            } label: {
                Label("再加一条", systemImage: "plus.circle")
            }
            .accessibilityIdentifier("knowledge-add-\(id)")
        }
    }

    private func save() async {
        guard let draft = model.draft() else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        let ok = await store.saveEntry(draft: draft, editing: editingID)
        if ok { dismiss() } else { errorMessage = store.errorMessage }
    }
}

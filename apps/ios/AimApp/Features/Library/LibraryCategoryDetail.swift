import SwiftUI

/// 分类详情。第一步只有三个分类有真实数据：身体感受、产检、危险信号；
/// 其余给出说明而不是空白页——空白页会让人以为坏了。
struct LibraryCategoryDetail: View {
    let category: LibraryCategoryID
    @Bindable var store: LibraryStore
    let agentStore: AgentStore

    @State private var showingAgent = false
    @State private var newQuestion = ""

    var body: some View {
        Group {
            switch category {
            case .safety: safetyList
            case .symptoms, .checkups: recordList
            case .questions: questionList
            case .paperwork: checklist(collection: "hangzhou")
            case .preparation: checklist(collection: "preparation")
            case .nutrition: knowledgeOrReference(collection: "nutrition")
            default: comingSoon
            }
        }
        .background(Color.aimCanvas)
        .navigationTitle(category.title)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    agentStore.focus(context: category.agentContext(from: store.snapshot))
                    showingAgent = true
                } label: {
                    Image(systemName: "wand.and.sparkles")
                }
                .accessibilityLabel("AIM")
            }
        }
        .fullScreenCover(isPresented: $showingAgent) {
            AgentView(store: agentStore) { showingAgent = false }
        }
    }

    private var safetyList: some View {
        List {
            ForEach(store.safetyRules) { rule in
                VStack(alignment: .leading, spacing: AimMetrics.space4) {
                    HStack(spacing: AimMetrics.space8) {
                        if rule.isUrgent {
                            Text("立即就医")
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, AimMetrics.space8)
                                .padding(.vertical, 2)
                                .background(Color.aimDangerSoft, in: Capsule())
                                .foregroundStyle(Color.aimDanger)
                        }
                        Text(rule.condition)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.aimTextPrimary)
                    }
                    Text(rule.action)
                        .font(.footnote)
                        .foregroundStyle(Color.aimTextSecondary)
                }
                .padding(.vertical, AimMetrics.space4)
                .listRowBackground(Color.aimSurface)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("library-safety-list")
    }

    private var recordList: some View {
        let records = store.records(in: category)
        return Group {
            if records.isEmpty {
                AimEmptyState(
                    title: "还没有内容",
                    message: "在时间线里记录，或者直接让 AIM 帮你记下来。",
                    actionTitle: "问问 AIM"
                ) {
                    agentStore.focus(context: category.agentContext(from: store.snapshot))
                    showingAgent = true
                }
            } else {
                List {
                    ForEach(records) { record in
                        VStack(alignment: .leading, spacing: AimMetrics.space4) {
                            Text(recordTitle(record))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.aimTextPrimary)
                            Text(record.occurredAt, style: .date)
                                .font(.caption)
                                .foregroundStyle(Color.aimTextTertiary)
                        }
                        .padding(.vertical, AimMetrics.space4)
                        .listRowBackground(Color.aimSurface)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .accessibilityIdentifier("library-record-list")
            }
        }
    }

    private var questionList: some View {
        let questions = store.snapshot.records
            .filter { $0.type == .question }
            .sorted { $0.occurredAt > $1.occurredAt }
        return List {
            Section {
                HStack(spacing: AimMetrics.space8) {
                    TextField("想问医生什么？", text: $newQuestion, axis: .vertical)
                        .accessibilityIdentifier("library-question-field")
                    Button {
                        let text = newQuestion
                        newQuestion = ""
                        Task { await store.addQuestion(text) }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.aimAccent)
                    }
                    .buttonStyle(.plain)
                    .disabled(newQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("library-question-add")
                }
                .listRowBackground(Color.aimSurface)
            } footer: {
                Text("攒下来的问题，下次产检一次带走。")
            }

            ForEach(questions) { record in
                let answered: Bool = {
                    guard case let .question(data) = record.structuredData else { return false }
                    return data.answered
                }()
                Button {
                    guard !answered else { return }
                    Task { await store.markQuestionAnswered(record, answer: nil) }
                } label: {
                    HStack(alignment: .top, spacing: AimMetrics.space8) {
                        Image(systemName: answered ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(answered ? Color.aimSuccess : Color.aimTextTertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.content ?? "")
                                .foregroundStyle(answered ? Color.aimTextTertiary : Color.aimTextPrimary)
                                .strikethrough(answered)
                            if case let .question(data) = record.structuredData,
                               let answer = data.answer, !answer.isEmpty {
                                Text(answer)
                                    .font(.footnote)
                                    .foregroundStyle(Color.aimTextSecondary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.aimSurface)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("library-question-list")
    }

    private func checklist(collection: String) -> some View {
        let items = store.collections[collection]?.items ?? []
        return List {
            ForEach(items) { item in
                Button {
                    Task { await store.toggleChecklistItem(collection: collection, itemID: item.id) }
                } label: {
                    HStack(alignment: .top, spacing: AimMetrics.space8) {
                        let done = store.isChecked(collection: collection, itemID: item.id)
                        Image(systemName: done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(done ? Color.aimSuccess : Color.aimTextTertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.aimTextPrimary)
                            Text(item.summary)
                                .font(.footnote)
                                .foregroundStyle(Color.aimTextSecondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.aimSurface)
                .accessibilityIdentifier("library-checklist-\(item.id)")
            }

            if let source = store.collections[collection] {
                Section {
                    // 政策与清单必须能追溯来源，见 ADR-0008 安全基线。
                    Text("来源：\(source.source)")
                        .font(.caption)
                        .foregroundStyle(Color.aimTextTertiary)
                }
                .listRowBackground(Color.aimSurface)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("library-checklist-\(collection)")
    }

    /// 只读参考内容。饮食提示不是清单——没有「做完」这个状态，
    /// 所以不给勾选框，避免暗示它是待办。
    /// 有用户条目就先展示用户条目，静态基线作为「基线参考」放下方。
    @ViewBuilder
    private func knowledgeOrReference(collection: String) -> some View {
        let entries = category.entries(in: store.snapshot)
        if entries.isEmpty {
            reference(collection: collection)
        } else {
            List {
                Section("我的资料") {
                    ForEach(entries) { entry in
                        NavigationLink { KnowledgeDetailView(entry: entry) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Color.aimTextPrimary)
                                Text(entry.subtitle)
                                    .font(.footnote)
                                    .foregroundStyle(Color.aimTextSecondary)
                            }
                        }
                        .listRowBackground(Color.aimSurface)
                    }
                }
                if let source = store.collections[collection] {
                    Section("基线参考") {
                        ForEach(source.items) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.subheadline)
                                Text(item.summary)
                                    .font(.footnote)
                                    .foregroundStyle(Color.aimTextSecondary)
                            }
                            .listRowBackground(Color.aimSurface)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .accessibilityIdentifier("library-knowledge-list")
        }
    }

    private func reference(collection: String) -> some View {
        let items = store.collections[collection]?.items ?? []
        return List {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: AimMetrics.space4) {
                    Text(item.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.aimTextPrimary)
                    Text(item.summary)
                        .font(.footnote)
                        .foregroundStyle(Color.aimTextSecondary)
                }
                .padding(.vertical, AimMetrics.space4)
                .listRowBackground(Color.aimSurface)
            }
            if let source = store.collections[collection] {
                Section {
                    Text("来源：\(source.source)。具体尺度以产检医生的意见为准。")
                        .font(.caption)
                        .foregroundStyle(Color.aimTextTertiary)
                }
                .listRowBackground(Color.aimSurface)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("library-reference-\(collection)")
    }

    private func recordTitle(_ record: RecordItem) -> String {
        if let title = record.title, !title.isEmpty { return title }
        switch record.structuredData {
        case let .symptom(data): return data.symptoms.joined(separator: "、")
        case let .checkup(data): return data.examItems
        default: return record.content ?? "记录"
        }
    }

    private var comingSoon: some View {
        AimEmptyState(
            title: category.title,
            message: category.summary(from: store.snapshot).headline,
            actionTitle: "问问 AIM"
        ) {
            agentStore.focus(context: category.agentContext(from: store.snapshot))
            showingAgent = true
        }
        .frame(maxHeight: .infinity)
    }
}

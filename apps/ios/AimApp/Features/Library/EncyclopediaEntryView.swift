import SwiftUI

/// 百科条目详情。正文按需拉取；推荐问题点一下就带着这条去问 AIM 并直接发出。
struct EncyclopediaEntryView: View {
    let entryID: String
    let store: LibraryStore
    let agentStore: AgentStore

    @State private var entry: EncyclopediaEntry?
    @State private var failed = false
    @State private var showingAgent = false
    @State private var countingFetalMovement = false

    var body: some View {
        Group {
            if let entry {
                content(entry)
            } else if failed {
                AimErrorState(message: "这条资料暂时打不开") { Task { await load() } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.aimCanvas)
        .navigationTitle(entry?.title ?? "")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .task(id: entryID) { await load() }
        .fullScreenCover(isPresented: $showingAgent) {
            AgentView(store: agentStore) { showingAgent = false }
        }
        .fullScreenCover(isPresented: $countingFetalMovement) {
            FetalMovementCounterView(agentStore: agentStore) { countingFetalMovement = false }
        }
    }

    private func load() async {
        failed = false
        do { entry = try await store.entry(id: entryID) } catch { failed = true }
    }

    private func content(_ entry: EncyclopediaEntry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AimMetrics.space12) {
                HStack(spacing: AimMetrics.space8) {
                    if let name = store.encyclopedia.topics.first(where: { $0.id == entry.topic })?.name {
                        tag(name)
                    }
                    if let weeks = entry.weeksLabel { tag(weeks) }
                }
                Text(entry.summary)
                    .font(.body)
                    .foregroundStyle(Color.aimTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(Array(entry.sections.enumerated()), id: \.offset) { _, section in
                    VStack(alignment: .leading, spacing: AimMetrics.space8) {
                        Text(section.heading).font(.headline).foregroundStyle(Color.aimTextPrimary)
                        Text(section.text)
                            .font(.subheadline)
                            .foregroundStyle(Color.aimTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .aimCard()
                }

                if entry.isPolicy, let link = entry.link.flatMap(URL.init(string:)) {
                    Link(destination: link) {
                        Label("到官方渠道核对", systemImage: "arrow.up.right.square")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .aimCard()
                    .accessibilityIdentifier("encyclopedia-policy-link")
                }

                askCard(entry)

                if !entry.related.isEmpty {
                    VStack(alignment: .leading, spacing: AimMetrics.space8) {
                        Text("相关").font(.headline).foregroundStyle(Color.aimTextPrimary)
                        ForEach(entry.related) { related in
                            NavigationLink {
                                EncyclopediaEntryView(entryID: related.id, store: store, agentStore: agentStore)
                            } label: {
                                HStack {
                                    Text(related.title).font(.subheadline).foregroundStyle(Color.aimTextPrimary)
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.aimTextTertiary)
                                }
                                // 整行可点：没有这一行，标题与箭头之间的空白点不中。
                                .contentShape(Rectangle())
                            }
                            .accessibilityIdentifier("encyclopedia-related-\(related.id)")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .aimCard()
                }

                if entry.id == "body.fetal-movement" {
                    Button { countingFetalMovement = true } label: {
                        Label("开始数胎动", systemImage: "hand.tap")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("encyclopedia-start-fetal-movement")
                }

                Text(footer(entry))
                    .font(.caption2)
                    .foregroundStyle(Color.aimTextTertiary)
                    .padding(.horizontal, AimMetrics.space4)
            }
            .padding(.horizontal, AimMetrics.space16)
            .padding(.bottom, AimMetrics.space28)
        }
    }

    private func askCard(_ entry: EncyclopediaEntry) -> some View {
        VStack(alignment: .leading, spacing: AimMetrics.space8) {
            Label("问问 AIM", systemImage: "wand.and.sparkles")
                .font(.headline)
                .foregroundStyle(Color.aimAccent)
            ForEach(Array(entry.ask.enumerated()), id: \.offset) { index, question in
                Button {
                    agentStore.prepareAnalysis(question, context: AgentContext(
                        title: "百科：\(entry.title)",
                        summary: "条目编号 \(entry.id)\n\(entry.summary)"))
                    showingAgent = true
                } label: {
                    HStack {
                        Text(question).font(.subheadline).foregroundStyle(Color.aimTextPrimary)
                        Spacer()
                        Image(systemName: "arrow.up.circle.fill").foregroundStyle(Color.aimAccent)
                    }
                    .padding(.vertical, AimMetrics.space4)
                    // `.plain` 样式下只有文字和图标接收点击，Spacer 留出的空白点不中；
                    // 让整行都可点，否则点在行中间没有反应。
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("encyclopedia-ask-\(index)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .aimCard()
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, AimMetrics.space8)
            .padding(.vertical, 2)
            .background(Color.aimAccentSoft, in: Capsule())
            .foregroundStyle(Color.aimAccent)
    }

    private func footer(_ entry: EncyclopediaEntry) -> String {
        let review = entry.isDraft ? "草稿，尚未审核" : "\(entry.reviewedAt ?? "") 核对"
        let policy = entry.isPolicy ? "政策以官方最新规定为准。" : "具体情况以产检医生的意见为准。"
        return "来源：\(entry.source)。\(review)。\(policy)"
    }
}

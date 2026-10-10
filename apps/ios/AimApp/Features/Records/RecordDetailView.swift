import SwiftUI

struct RecordDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSessionStore.self) private var session
    let record: RecordItem
    @Bindable var store: RecordStore
    let planStore: PlanStore
    let agentStore: AgentStore
    @State private var showingEditor = false
    @State private var showingDeleteConfirmation = false
    @State private var showingTaskSheet = false
    @State private var showingAgent = false
    @State private var viewingImage: IdentifiedImage?

    private var currentRecord: RecordItem {
        store.snapshot?.records.first(where: { $0.id == record.id }) ?? record
    }

    /// 家庭可见的记录家里任何成员都能改；仅自己可见的只有作者能改。与后端一致。
    private var canEdit: Bool { currentRecord.isEditable(by: session.accountID) }
    private var isAuthor: Bool { session.accountID == currentRecord.authorAccountID }

    var body: some View {
        // 产检报告有自己的详情页：指标对比、化验项、把异常项加入想问医生。
        if record.type == .checkup {
            CheckupReportView(record: record, store: store, planStore: planStore, agentStore: agentStore)
        } else {
            genericDetail
        }
    }

    private var genericDetail: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label(currentRecord.type.displayName, systemImage: currentRecord.type.symbolName)
                        .foregroundStyle(Color.aimAccent)
                    Text(currentRecord.displayTitle).font(.title2.weight(.semibold))
                    Text(currentRecord.occurredAt, format: .dateTime.year().month().day().hour().minute())
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .aimCard()
            }
            .listRowBackground(Color.clear)

            contentSection
            if !currentRecord.attachmentRefs.isEmpty {
                Section("图片") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AimMetrics.space8) {
                            ForEach(currentRecord.attachmentRefs, id: \.self) { id in
                                AttachmentThumbnail(id: id, environment: session.environment) {
                                    viewingImage = IdentifiedImage(image: $0)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            Section("记录信息") {
                LabeledContent("记录人", value: isAuthor ? "我" : "家庭成员")
                Label(currentRecord.visibility.displayName, systemImage: currentRecord.visibility == .family ? "person.2" : "lock")
            }
            Section {
                Button("转为待办") { showingTaskSheet = true }
                Button("让 Agent 分析当前记录") {
                    agentStore.prepareAnalysis(
                        analysisPrompt(for: currentRecord),
                        context: currentRecord.agentContext
                    )
                    showingAgent = true
                }
                if canEdit {
                    // 胎动记录由计数页生成，通用编辑器改不了它的计数数据；只留删除。
                    if currentRecord.type.canEditInComposer {
                        Button("编辑记录") { showingEditor = true }
                    }
                    Button("删除记录", role: .destructive) { showingDeleteConfirmation = true }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("记录详情")
        .confirmationDialog("删除这条记录？", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("删除", role: .destructive) { Task { await delete() } }
        } message: { Text("删除后无法恢复。") }
        .sheet(isPresented: $showingEditor) {
            RecordComposerView(store: store, record: currentRecord) { showingEditor = false }
        }
        .sheet(isPresented: $showingTaskSheet) {
            RecordTaskSheet(record: currentRecord, store: store, planStore: planStore) { showingTaskSheet = false }
        }
        .fullScreenCover(isPresented: $showingAgent) {
            AgentView(store: agentStore) { showingAgent = false }
        }
        .fullScreenCover(item: $viewingImage) { item in
            AttachmentViewer(image: item.image) { viewingImage = nil }
        }
    }

    @ViewBuilder
    private var contentSection: some View {
        switch currentRecord.structuredData {
        case let .symptom(data):
            Section("身体感受") {
                LabeledContent("症状", value: data.symptoms.joined(separator: "、"))
                LabeledContent("程度", value: "\(data.severity) / 5")
                if let note = data.note, !note.isEmpty { Text(note) }
            }
        case .checkup:
            // 产检走 CheckupReportView，到不了这里。
            EmptyView()
        case .note:
            Section("内容") { Text(currentRecord.content ?? "没有补充内容") }
        case let .question(data):
            Section("想问医生") {
                Text(currentRecord.content ?? "")
                if let answer = data.answer, !answer.isEmpty {
                    LabeledContent("医生的回答", value: answer)
                } else {
                    Text(data.answered ? "已解答" : "还没问")
                        .foregroundStyle(.secondary)
                }
            }
        case let .checklist(data):
            Section("清单") {
                LabeledContent("条目", value: record.displayTitle)
                LabeledContent("状态", value: data.done ? "已完成" : "待完成")
            }
        case let .knowledge(data):
            Section("资料") {
                if let body = data.body { Text(body) }
                if let reason = data.reason { Text(reason) }
                ForEach(data.steps ?? [], id: \.self) { Text($0) }
            }
        case let .fetalMovement(data):
            Section("胎动") {
                LabeledContent("次数", value: "\(data.count) 次")
                LabeledContent("用时", value: FetalMovementFormat.duration(data.durationSeconds))
                LabeledContent("结果", value: FetalMovementFormat.summary(data))
            }
        case .unknown:
            Section { Text("这类记录暂不支持完整展示。") }
        }
    }

    private func analysisPrompt(for record: RecordItem) -> String {
        "请帮我理解这条孕期记录，并告诉我接下来需要留意什么：\n\n类型：\(record.type.displayName)\n发生时间：\(record.occurredAt.formatted(date: .abbreviated, time: .shortened))\n内容：\(record.displayTitle)\n\(record.displaySummary)"
    }

    private func delete() async {
        if await store.delete(recordID: record.id) { dismiss() }
    }
}

struct RecordTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    let record: RecordItem
    @Bindable var store: RecordStore
    let planStore: PlanStore
    let onCreated: () -> Void
    @State private var title: String
    @State private var description: String = ""
    @State private var hasDueDate = false
    @State private var dueAt = Date.now

    init(record: RecordItem, store: RecordStore, planStore: PlanStore, onCreated: @escaping () -> Void) {
        self.record = record
        self.store = store
        self.planStore = planStore
        self.onCreated = onCreated
        _title = State(initialValue: "跟进：\(record.displayTitle)")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("待办内容") {
                    TextField("待办标题", text: $title)
                    TextField("补充说明（可选）", text: $description, axis: .vertical)
                }
                Section {
                    Toggle("设置截止时间", isOn: $hasDueDate)
                    if hasDueDate { DatePicker("截止时间", selection: $dueAt, displayedComponents: [.date, .hourAndMinute]) }
                }
                if let error = store.errorMessage { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("转为待办")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认创建") { Task { await create() } }
                        .disabled(title.trimmed.isEmpty || store.isSaving)
                }
            }
        }
    }

    private func create() async {
        if await store.createTask(from: record, title: title.trimmed, description: description.trimmed.nilIfEmpty, dueAt: hasDueDate ? dueAt : nil) != nil {
            await planStore.load()
            onCreated()
            dismiss()
        }
    }
}

/// 取一张附件图片的请求。只接受附件编号，带上登录信息。
enum AttachmentRequest {
    static func make(id: String, environment: APIEnvironment) -> URLRequest? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        var request = environment.businessRequest(path: "/api/v1/attachments/\(uuid.uuidString.lowercased())")
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        return request
    }
}

struct IdentifiedImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// 记录上挂的一张图片。加载失败显示占位，不影响页面其它内容。
struct AttachmentThumbnail: View {
    let id: String
    let environment: APIEnvironment
    let onOpen: (UIImage) -> Void
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Button { onOpen(image) } label: {
                    Image(uiImage: image).resizable().scaledToFill()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("查看大图")
            } else if failed {
                Image(systemName: "photo")
                    .foregroundStyle(Color.aimTextTertiary)
                    .accessibilityLabel("图片加载失败")
            } else {
                ProgressView()
            }
        }
        .frame(width: 96, height: 96)
        .background(Color.aimSurfaceSunken)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // 报告单多是白底，不描边的话和白色列表行连成一片，看不出是一张图。
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.aimRail, lineWidth: 1))
        .task(id: id) {
            guard let request = AttachmentRequest.make(id: id, environment: environment),
                  let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let loaded = UIImage(data: data)
            else {
                failed = true
                return
            }
            image = loaded
        }
    }
}

/// 全屏看大图：双指缩放，点一下关闭。
struct AttachmentViewer: View {
    let image: UIImage
    let onClose: () -> Void
    @State private var scale: CGFloat = 1
    @State private var settledScale: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .gesture(
                    MagnifyGesture()
                        .onChanged { scale = min(max(1, settledScale * $0.magnification), 5) }
                        .onEnded { _ in settledScale = scale }
                )
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onClose)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("图片，点一下关闭")
        .accessibilityAddTraits(.isButton)
    }
}

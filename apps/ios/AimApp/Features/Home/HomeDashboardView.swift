import PhotosUI
import SwiftUI

/// 首页：今天孕几周、宝宝多大、还有多久见面；这一周的变化、今天要做的事、常用入口、家里的动静、安全提示。
struct HomeDashboardView: View {
    @Environment(AppSessionStore.self) private var session
    @Bindable var store: HomeDashboardStore
    let recordStore: RecordStore
    let familyStore: FamilyStore
    let libraryStore: LibraryStore
    let agentStore: AgentStore
    /// 切到别的标签（待办、家庭）。
    let onSwitchTab: (MainTab) -> Void

    @State private var showingAgent = false
    @State private var recordType: RecordComposerTarget?
    @State private var choosingPhotoSource = false
    @State private var showingCamera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showingPhotoLibrary = false
    @State private var showingInvite = false
    @State private var showingSafety = false
    @State private var toast: AimToastMessage?

    private var myself: FamilyMember? {
        store.members.first { $0.accountID == session.accountID }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AimMetrics.space12) {
                    header
                    heroCard
                    weekCard
                    todayCard
                    quickActions
                    familyCard
                    safetyBar
                }
                .padding(.horizontal, AimMetrics.space16)
                .padding(.bottom, AimMetrics.space28)
            }
            .background(Color.aimCanvas)
            .refreshable { await store.load() }
            .task { await store.load() }
            // 「欢迎回来」「已加入某某家庭」这类一次性提示：启动默认进首页，就在这里显示。
            .onAppear {
                if let notice = session.welcomeBackNotice {
                    toast = AimToastMessage(text: notice, undoTitle: "", accessibilityIdentifier: "home-welcome-back")
                    session.welcomeBackNotice = nil
                } else if let notice = session.familyNotice {
                    toast = AimToastMessage(text: notice, undoTitle: "", accessibilityIdentifier: "home-family-notice")
                    session.familyNotice = nil
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .aimDataChanged)) { _ in
                Task { await store.load() }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Int.self) { week in
                WeekDetailView(store: store, initialWeek: week, agentStore: agentStore)
            }
            .fullScreenCover(isPresented: $showingAgent) {
                AgentView(store: agentStore) { showingAgent = false }
            }
            .sheet(item: $recordType) { target in
                RecordComposerView(store: recordStore, suggestedType: target.type) {
                    recordType = nil
                    NotificationCenter.default.post(name: .aimDataChanged, object: nil, userInfo: ["kinds": ["record"]])
                }
            }
            .sheet(isPresented: $showingInvite) { InviteMemberSheet(store: familyStore) }
            .sheet(isPresented: $showingSafety) {
                NavigationStack {
                    LibraryCategoryDetail(category: .safety, store: libraryStore, agentStore: agentStore)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("完成") { showingSafety = false }
                            }
                        }
                }
            }
            .confirmationDialog("拍报告", isPresented: $choosingPhotoSource, titleVisibility: .visible) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("拍照") { showingCamera = true }
                }
                Button("从相册选") { showingPhotoLibrary = true }
                Button("取消", role: .cancel) {}
            } message: {
                Text("选好后交给 AIM，补一句话再发出去。")
            }
            .photosPicker(isPresented: $showingPhotoLibrary, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                photoItem = nil
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        sendToAgent(image)
                    }
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { image in
                    showingCamera = false
                    if let image { sendToAgent(image) }
                }
                .ignoresSafeArea()
            }
            .aimToast($toast)
        }
    }

    // MARK: - 顶部

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now.formatted(.dateTime.month().day().weekday(.wide).locale(Locale(identifier: "zh_CN"))))
                    .font(.caption)
                    .foregroundStyle(Color.aimTextSecondary)
                Text("\(HomeDashboardStore.greeting(at: .now))，\(myself?.displayName ?? "你好")")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.aimTextPrimary)
                    .accessibilityIdentifier("home-greeting")
            }
            Spacer()
            Button { onSwitchTab(.family) } label: {
                HStack(spacing: -8) {
                    ForEach(store.members.prefix(3)) { member in
                        MemberAvatar(name: member.displayName, size: 30, highlighted: member.accountID == session.accountID)
                            .overlay(Circle().stroke(Color.aimCanvas, lineWidth: 2))
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("家庭")
            Button {
                agentStore.focus(context: nil)
                showingAgent = true
            } label: {
                Image(systemName: "wand.and.sparkles")
                    .font(.subheadline)
                    .foregroundStyle(Color.aimAccent)
                    .frame(width: 34, height: 34)
                    .background(Color.aimAccentSoft, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.leading, AimMetrics.space8)
            .accessibilityLabel("AIM")
            .accessibilityIdentifier("global-agent-button")
        }
        .padding(.top, AimMetrics.space8)
    }

    // MARK: - 孕周主卡

    @ViewBuilder
    private var heroCard: some View {
        if let pregnancy = store.pregnancy, let progress = store.progress {
            let week = store.thisWeek ?? WeeklyContentBook.earlyFallback
            NavigationLink(value: pregnancy.weeks) {
                VStack(spacing: AimMetrics.space16) {
                    HStack(spacing: AimMetrics.space16) {
                        ProgressRing(fraction: progress.fraction) {
                            VStack(spacing: 2) {
                                Text(week.fruit).font(.system(size: 34))
                                Text("像\(week.fruitName)")
                                    .font(.caption2)
                                    .foregroundStyle(Color.aimTextSecondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                        }
                        .frame(width: ringSize, height: ringSize)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(progress.stage.title)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(Color.aimAccentSoft, in: Capsule())
                                .foregroundStyle(Color.aimAccent)
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text("\(pregnancy.weeks)").font(.system(size: 32, weight: .semibold, design: .rounded))
                                Text("周").font(.subheadline)
                                Text("+\(pregnancy.days)").font(.system(size: 20, weight: .semibold, design: .rounded))
                                Text("天").font(.subheadline)
                            }
                            .foregroundStyle(Color.aimTextPrimary)
                            if let size = week.sizeText {
                                Text(size).font(.caption).foregroundStyle(Color.aimTextSecondary)
                            }
                            Text(progress.daysLeft >= 0 ? "距预产期 \(progress.daysLeft) 天" : "已过预产期 \(-progress.daysLeft) 天")
                                .font(.caption)
                                .foregroundStyle(progress.daysLeft >= 0 ? Color.aimTextSecondary : Color.aimDanger)
                        }
                        Spacer(minLength: 0)
                    }
                    StageBar(progress: progress)
                }
                .padding(AimMetrics.space16)
                .background(Color.aimSurface, in: RoundedRectangle(cornerRadius: AimMetrics.radiusCard))
                .overlay(RoundedRectangle(cornerRadius: AimMetrics.radiusCard).stroke(Color.aimSeparator))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home-hero")
        } else if let error = store.pregnancyError {
            retryCard(error)
        } else {
            card { ProgressView().frame(maxWidth: .infinity, minHeight: 120) }
        }
    }

    @ScaledMetric private var ringSize: CGFloat = 104

    // MARK: - 这一周

    @ViewBuilder
    private var weekCard: some View {
        if let pregnancy = store.pregnancy {
            let week = store.thisWeek ?? WeeklyContentBook.earlyFallback
            NavigationLink(value: pregnancy.weeks) {
                card {
                    VStack(alignment: .leading, spacing: AimMetrics.space8) {
                        HStack {
                            Text("这一周").font(.headline)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.aimTextTertiary)
                        }
                        weekLine("stroller", "宝宝", week.baby)
                        weekLine("heart", "妈妈", week.mom)
                        if let tip = week.tips.first { weekLine("lightbulb", "提示", tip) }
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home-week-card")
        }
    }

    private func weekLine(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: AimMetrics.space8) {
            Image(systemName: symbol).foregroundStyle(Color.aimAccent).frame(width: 20)
            (Text(title).fontWeight(.semibold) + Text("　\(text)"))
                .font(.subheadline)
                .foregroundStyle(Color.aimTextPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 今天

    @ViewBuilder
    private var todayCard: some View {
        card {
            VStack(alignment: .leading, spacing: AimMetrics.space8) {
                HStack {
                    Text("今天").font(.headline)
                    Spacer()
                    Button("全部 \(store.todayTotal) 项 ›") { onSwitchTab(.tasks) }
                        .font(.caption)
                        .foregroundStyle(Color.aimAccent)
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("home-today-all")
                }
                if let error = store.tasksError, store.todayTasks.isEmpty {
                    Button("加载失败，点这里重试") { Task { await store.load() } }
                        .font(.subheadline)
                        .help(error)
                } else if store.todayTasks.isEmpty {
                    Text("今天没有安排").font(.subheadline).foregroundStyle(Color.aimTextSecondary)
                    if let next = store.nextTask, let due = next.dueAt {
                        Text("下一件：\(due.formatted(.dateTime.month().day().locale(Locale(identifier: "zh_CN")))) \(next.title)")
                            .font(.caption)
                            .foregroundStyle(Color.aimTextSecondary)
                    }
                }
                ForEach(store.todayTasks) { task in
                    HStack(spacing: AimMetrics.space12) {
                        Button { Task { await complete(task) } } label: {
                            Image(systemName: "circle").font(.title3).foregroundStyle(Color.aimRail)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("完成「\(task.title)」")
                        Text(task.title).font(.subheadline).foregroundStyle(Color.aimTextPrimary).lineLimit(1)
                        Spacer()
                        if isOverdue(task) {
                            Text("已逾期").font(.caption).foregroundStyle(Color.aimDanger)
                        } else if let assignee = assigneeName(task) {
                            Text(assignee).font(.caption).foregroundStyle(Color.aimTextSecondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func isOverdue(_ task: TaskItem) -> Bool {
        guard let due = task.dueAt else { return false }
        return due < TimelineBuilder.calendar.startOfDay(for: .now)
    }

    private func assigneeName(_ task: TaskItem) -> String? {
        guard let id = task.assignedMemberID, id != session.accountID else { return nil }
        return store.members.first { $0.accountID == id }?.displayName
    }

    private func complete(_ task: TaskItem) async {
        if await store.complete(task) {
            toast = AimToastMessage(text: "已完成「\(task.title)」", undoTitle: "", accessibilityIdentifier: "home-completed")
            NotificationCenter.default.post(name: .aimDataChanged, object: nil, userInfo: ["kinds": ["task"]])
        }
    }

    // MARK: - 快捷入口

    private var quickActions: some View {
        card {
            HStack(spacing: 0) {
                quickAction("square.and.pencil", "记一笔", id: "home-quick-record") { recordType = RecordComposerTarget(type: nil) }
                quickAction("camera", "拍报告", id: "home-quick-photo") { choosingPhotoSource = true }
                quickAction("scalemass", "体重血压", id: "home-quick-metrics") { recordType = RecordComposerTarget(type: .checkup) }
                quickAction("bubble.left.and.text.bubble.right", "问 AIM", id: "home-quick-agent") {
                    agentStore.focus(context: nil)
                    showingAgent = true
                }
            }
        }
    }

    private func quickAction(_ symbol: String, _ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 19))
                    .foregroundStyle(Color.aimAccent)
                    .frame(width: 46, height: 46)
                    .background(Color.aimAccentSoft, in: RoundedRectangle(cornerRadius: 14))
                Text(title).font(.caption).foregroundStyle(Color.aimTextPrimary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func sendToAgent(_ image: UIImage) {
        guard let dataURL = image.aimJPEGDataURL(maxEdge: 1600) else { return }
        agentStore.prepareImage(dataURL)
        showingAgent = true
    }

    // MARK: - 家里最近

    @ViewBuilder
    private var familyCard: some View {
        if store.members.count <= 1 {
            Button { showingInvite = true } label: {
                card {
                    HStack(spacing: AimMetrics.space12) {
                        Image(systemName: "person.2.badge.plus").font(.title3).foregroundStyle(Color.aimAccent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("邀请家人一起").font(.subheadline.weight(.semibold))
                            Text("共享孕期、待办和记录，一起照顾。").font(.caption).foregroundStyle(Color.aimTextSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.aimTextTertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home-invite-card")
        } else {
            Button { onSwitchTab(.family) } label: {
                card {
                    VStack(alignment: .leading, spacing: AimMetrics.space8) {
                        HStack {
                            Text("家里最近").font(.headline)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.aimTextTertiary)
                        }
                        if store.recentActivity.isEmpty {
                            Text(store.activityError == nil ? "还没有动态" : "加载失败，下拉重试")
                                .font(.subheadline).foregroundStyle(Color.aimTextSecondary)
                        }
                        ForEach(store.recentActivity) { item in
                            HStack(alignment: .firstTextBaseline, spacing: AimMetrics.space8) {
                                Text(item.sentence).font(.subheadline).foregroundStyle(Color.aimTextPrimary).lineLimit(2)
                                Spacer(minLength: 0)
                                Text(item.createdAt.formatted(.relative(presentation: .named).locale(Locale(identifier: "zh_CN"))))
                                    .font(.caption2).foregroundStyle(Color.aimTextTertiary)
                            }
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home-family-card")
        }
    }

    // MARK: - 安全提示

    private var safetyBar: some View {
        Button { showingSafety = true } label: {
            HStack(spacing: AimMetrics.space8) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text("出血、破水、胎动明显减少——立即就医").font(.subheadline)
                Spacer()
                Image(systemName: "chevron.right").font(.caption)
            }
            .foregroundStyle(Color.aimDanger)
            .padding(AimMetrics.space12)
            .background(Color.aimDangerSoft, in: RoundedRectangle(cornerRadius: AimMetrics.radiusButton))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home-safety")
    }

    // MARK: - 通用

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AimMetrics.space16)
            .background(Color.aimSurface, in: RoundedRectangle(cornerRadius: AimMetrics.radiusCard))
            .overlay(RoundedRectangle(cornerRadius: AimMetrics.radiusCard).stroke(Color.aimSeparator))
    }

    private func retryCard(_ message: String) -> some View {
        Button { Task { await store.load() } } label: {
            card {
                VStack(alignment: .leading, spacing: 4) {
                    Text("加载失败，点这里重试").font(.subheadline).foregroundStyle(Color.aimAccent)
                    Text(message).font(.caption).foregroundStyle(Color.aimTextTertiary).lineLimit(2)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// 主界面的标签。首页用它切到别的标签。
enum MainTab: Hashable {
    case home, tasks, agent, library, family
}

/// `sheet(item:)` 需要 Identifiable：新增记录面板预选的类型。
struct RecordComposerTarget: Identifiable {
    let type: RecordType?
    var id: String { type?.rawValue ?? "any" }
}

/// 孕期进度圆环，中间放内容。
struct ProgressRing<Content: View>: View {
    let fraction: Double
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Circle().stroke(Color.aimRail.opacity(0.5), lineWidth: 6)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Color.aimAccent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            content().padding(10)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("孕期已走过 \(Int(fraction * 100))%")
    }
}

/// 三段条：孕早、中、晚期，当前阶段按阶段内进度填充。
struct StageBar: View {
    let progress: PregnancyProgress
    private let stages: [PregnancyStage] = [.early, .middle, .late]

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(stages, id: \.self) { stage in
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.aimRail.opacity(0.5))
                            Capsule().fill(Color.aimAccent).frame(width: proxy.size.width * fill(for: stage))
                        }
                    }
                    .frame(height: 4)
                }
            }
            HStack {
                ForEach(stages, id: \.self) { stage in
                    Text(stage.title)
                        .font(.caption2)
                        .foregroundStyle(stage == progress.stage ? Color.aimAccent : Color.aimTextTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func fill(for stage: PregnancyStage) -> CGFloat {
        let order: [PregnancyStage] = [.early, .middle, .late]
        let current = order.firstIndex(of: progress.stage) ?? 0
        let index = order.firstIndex(of: stage) ?? 0
        if index < current { return 1 }
        if index > current { return 0 }
        return progress.stageFraction
    }
}

/// 系统相机。拍完或取消都回调；取消时为 nil。
struct CameraPicker: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void
        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onFinish(nil) }
    }
}

extension UIImage {
    /// 缩到最长边 `maxEdge` 的 JPEG data URL，交给 AIM 网页。网页发送前还会再压一次。
    func aimJPEGDataURL(maxEdge: CGFloat) -> String? {
        let scale = min(1, maxEdge / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
        guard let data = resized.jpegData(compressionQuality: 0.8) else { return nil }
        return "data:image/jpeg;base64,\(data.base64EncodedString())"
    }
}

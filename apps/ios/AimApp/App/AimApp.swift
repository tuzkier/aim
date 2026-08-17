import SwiftUI

@main
struct AimApp: App {
    @State private var session = AppSessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .tint(.aimAccent)
        }
    }
}

private struct RootView: View {
    @Environment(AppSessionStore.self) private var session

    var body: some View {
        Group {
            if session.isConfigured {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
    }
}

private struct MainTabView: View {
    @Environment(AppSessionStore.self) private var session
    @State private var todayStore = TodayStore()
    @State private var planStore = PlanStore()
    @State private var recordStore = RecordStore()
    @State private var familyStore = FamilyStore()
    @State private var selectedTab: AimTab = .today
    @State private var showingAgent = false

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView(store: todayStore)
                .tabItem { Label("今天", systemImage: "sun.max") }
                .tag(AimTab.today)

            PlanView(store: planStore)
                .tabItem { Label("计划", systemImage: "calendar") }
                .tag(AimTab.plan)

            RecordsView(store: recordStore, planStore: planStore)
                .tabItem { Label("记录", systemImage: "note.text") }
                .tag(AimTab.records)

            FamilyView(store: familyStore)
                .tabItem { Label("家庭", systemImage: "person.2") }
                .tag(AimTab.family)
        }
        .overlay(alignment: .bottomTrailing) {
            Button { showingAgent = true } label: {
                Image(systemName: "sparkles")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.aimAccent, in: Circle())
                    .overlay { Circle().stroke(.white.opacity(0.75), lineWidth: 2) }
                    .shadow(color: Color.black.opacity(0.18), radius: 12, y: 6)
            }
            .accessibilityLabel("问一问")
            .accessibilityHint("打开 Agent，并带入当前页面内容")
            .accessibilityIdentifier("global-agent-button")
            .padding(.trailing, 18)
            .padding(.bottom, 76)
        }
        .task {
            await reloadRepositories()
        }
        .onChange(of: session.pregnancyID) { _, _ in
            Task { await reloadRepositories() }
        }
        .fullScreenCover(isPresented: $showingAgent) {
            AgentSheet(context: currentAgentContext)
        }
    }

    private var currentAgentContext: AgentContext {
        switch selectedTab {
        case .today:
            guard let snapshot = todayStore.snapshot else {
                return AgentContext(title: "今天", summary: "今天页正在准备孕期和优先事项。")
            }
            var lines = ["孕 " + String(snapshot.weeks) + " 周 " + String(snapshot.days) + " 天"]
            if let task = snapshot.priorityTask { lines.append("当前最重要：" + task.title) }
            if !snapshot.upcomingTasks.isEmpty {
                let upcoming = snapshot.upcomingTasks.prefix(2).map(\.title).joined(separator: "、")
                lines.append("接下来：" + upcoming)
            }
            return AgentContext(title: "今天", summary: lines.joined(separator: "\n"))
        case .plan:
            let openTasks = planStore.snapshot?.tasks.filter(\.isOpen) ?? []
            let summary: String
            if openTasks.isEmpty {
                summary = "当前没有未完成事项。"
            } else {
                summary = "未完成 " + String(openTasks.count) + " 项：" + openTasks.prefix(3).map(\.title).joined(separator: "、")
            }
            return AgentContext(title: "计划", summary: summary)
        case .records:
            let records = recordStore.snapshot?.records ?? []
            let summary: String
            if records.isEmpty {
                summary = "当前还没有记录。"
            } else {
                let recent = records.prefix(3).map { $0.type.displayName + "：" + $0.displayTitle }.joined(separator: "；")
                summary = "最近 " + String(min(records.count, 3)) + " 条：" + recent
            }
            return AgentContext(title: "记录", summary: summary)
        case .family:
            guard let snapshot = familyStore.snapshot else {
                return AgentContext(title: "家庭", summary: "家庭信息正在加载。")
            }
            let members = snapshot.members.map { $0.role.displayName }.joined(separator: "、")
            return AgentContext(title: "家庭", summary: "家庭：" + snapshot.name + "\n成员：" + members)
        }
    }

    private enum AimTab: Hashable {
        case today
        case plan
        case records
        case family
    }

    private func reloadRepositories() async {
        let repository = BusinessRepository(environment: session.environment)
        todayStore.repository = repository
        planStore.repository = repository
        recordStore.repository = repository
        familyStore.repository = repository
        await todayStore.load()
        await planStore.load()
        await recordStore.load()
        await familyStore.load()
    }
}

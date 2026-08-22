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
            if !session.isConfigured {
                OnboardingView()
            } else if session.pregnancyID == nil {
                // 没有孕期档案就没有孕周，计划和记录都无处安放。
                // 这里是准入门槛，不是可跳过的提示。
                PregnancySetupView()
            } else {
                MainTabView()
            }
        }
    }
}

private struct MainTabView: View {
    @Environment(AppSessionStore.self) private var session
    @State private var timelineStore = TimelineStore()
    @State private var planStore = PlanStore()
    @State private var recordStore = RecordStore()
    @State private var familyStore = FamilyStore()
    @State private var agentStore = AgentStore()
    @State private var libraryStore = LibraryStore()
    @State private var selectedTab: AimTab = .timeline

    var body: some View {
        TabView(selection: $selectedTab) {
            TimelineView(store: timelineStore, planStore: planStore, recordStore: recordStore, agentStore: agentStore)
                .tabItem { Label("孕期", systemImage: "heart.text.square") }
                .tag(AimTab.timeline)

            AgentView(store: agentStore)
                .tabItem { Label("AIM", systemImage: "wand.and.sparkles") }
                .tag(AimTab.agent)

            LibraryView(store: libraryStore, agentStore: agentStore)
                .tabItem { Label("资料库", systemImage: "books.vertical") }
                .tag(AimTab.library)

            FamilyView(store: familyStore)
                .tabItem { Label("家庭", systemImage: "person.2") }
                .tag(AimTab.family)
        }
        .task { await reloadRepositories() }
        .onChange(of: session.pregnancyID) { _, _ in
            Task { await reloadRepositories() }
        }
    }

    private enum AimTab: Hashable {
        case timeline
        case agent
        case library
        case family
    }

    private func reloadRepositories() async {
        let repository = BusinessRepository(environment: session.environment)
        timelineStore.repository = repository
        planStore.repository = repository
        recordStore.repository = repository
        familyStore.repository = repository
        // Agent 撤销「新建」类操作要直接调删除接口，不经过模型。
        agentStore.repository = repository
        libraryStore.repository = repository
        await timelineStore.load()
        await planStore.load()
        await recordStore.load()
        await familyStore.load()
        await libraryStore.load()
    }
}

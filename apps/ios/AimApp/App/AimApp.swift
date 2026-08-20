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
    @State private var timelineStore = TimelineStore()
    @State private var planStore = PlanStore()
    @State private var recordStore = RecordStore()
    @State private var familyStore = FamilyStore()
    @State private var agentStore = AgentStore()
    @State private var selectedTab: AimTab = .timeline

    var body: some View {
        TabView(selection: $selectedTab) {
            TimelineView(store: timelineStore, planStore: planStore, recordStore: recordStore, openAgent: openAgent)
                .tabItem { Label("孕期", systemImage: "heart.text.square") }
                .tag(AimTab.timeline)

            AgentView(store: agentStore)
                .tabItem { Label("Agent", systemImage: "wand.and.sparkles") }
                .tag(AimTab.agent)

            FamilyView(store: familyStore)
                .tabItem { Label("家庭", systemImage: "person.2") }
                .tag(AimTab.family)
        }
        .task { await reloadRepositories() }
        .onChange(of: session.pregnancyID) { _, _ in
            Task { await reloadRepositories() }
        }
    }

    /// Shared by every "ask the Agent about this" entry point in the app.
    /// Passing `autoSend` immediately asks that question; leaving it `nil`
    /// just brings the current page's context into the Agent tab so the
    /// user can decide what to type. Either way, this always continues the
    /// one shared conversation rather than opening a fresh, disconnected one.
    private func openAgent(context: AgentContext, autoSend: String?) {
        if let autoSend {
            agentStore.ask(autoSend, context: context, environment: session.environment)
        } else {
            agentStore.focus(context: context)
        }
        selectedTab = .agent
    }

    private enum AimTab: Hashable {
        case timeline
        case agent
        case family
    }

    private func reloadRepositories() async {
        let repository = BusinessRepository(environment: session.environment)
        timelineStore.repository = repository
        planStore.repository = repository
        recordStore.repository = repository
        familyStore.repository = repository
        await timelineStore.load()
        await planStore.load()
        await recordStore.load()
        await familyStore.load()
    }
}

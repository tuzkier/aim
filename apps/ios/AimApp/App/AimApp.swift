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
    @State private var showingAgent = false

    var body: some View {
        TabView {
            TodayView(store: todayStore)
                .tabItem { Label("今天", systemImage: "sun.max") }

            PlanView(store: planStore)
                .tabItem { Label("计划", systemImage: "calendar") }

            RecordsView(store: recordStore, planStore: planStore)
                .tabItem { Label("记录", systemImage: "note.text") }

            FamilyView(store: familyStore)
                .tabItem { Label("家庭", systemImage: "person.2") }

            Button {
                showingAgent = true
            } label: {
                Label("问一问", systemImage: "sparkles")
            }
            .tabItem { Label("Agent", systemImage: "sparkles") }
        }
        .task {
            await reloadRepositories()
        }
        .onChange(of: session.pregnancyID) { _, _ in
            Task { await reloadRepositories() }
        }
        .sheet(isPresented: $showingAgent) {
            AgentSheet()
        }
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

import SwiftUI

struct OnboardingView: View {
    @Environment(AppSessionStore.self) private var session
    @State private var store = OnboardingStore()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("从今天开始，一起把孕期过得更从容", systemImage: "heart.text.square")
                            .font(.title2.weight(.semibold))
                        Text("Aim 以家庭为单位，把每个阶段该做的事整理成计划。普通功能不依赖 Agent，Agent 会在需要时贯穿其中。")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                Section {
                    TextField("账号 ID", text: $store.accountID)
#if os(iOS)
                        .textInputAutocapitalization(.never)
#endif
                        .autocorrectionDisabled()
                    TextField("家庭 ID", text: $store.familyID)
#if os(iOS)
                        .textInputAutocapitalization(.never)
#endif
                        .autocorrectionDisabled()
                    TextField("孕期 ID", text: $store.pregnancyID)
#if os(iOS)
                        .textInputAutocapitalization(.never)
#endif
                        .autocorrectionDisabled()
                    SecureField("会话 Token", text: $store.bearerToken)
                } header: {
                    Text("连接当前家庭")
                } footer: {
                    Text("当前后端仍使用受控会话 Token。正式登录与邀请入口接入后，这些字段会由登录流程填充。")
                }

                if let errorMessage = store.errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }

                Section {
                    Button("进入我的孕期") {
                        _ = store.connect(using: session)
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("欢迎来到 Aim")
            .scrollContentBackground(.hidden)
            .background(Color.aimWarmBackground)
        }
    }
}

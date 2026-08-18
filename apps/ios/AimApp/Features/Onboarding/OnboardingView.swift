import SwiftUI

struct OnboardingView: View {
    @Environment(AppSessionStore.self) private var session
    @State private var store = OnboardingStore()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("先进入 Aim，孕期信息稍后补充", systemImage: "heart.text.square")
                            .font(.title2.weight(.semibold))
                        Text("先用手机号进入家庭空间。预产期不是门槛，准备好后再补充，Aim 才会开始生成对应阶段的计划。")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                Section {
                    TextField("手机号", text: $store.phone)
#if os(iOS)
                        .keyboardType(.phonePad)
#endif
                        .autocorrectionDisabled()
                } header: {
                    Text("先创建你的账号")
                } footer: {
                    Text("当前为本地演示环境，不发送短信。账号和家庭会自动创建，预产期可以稍后填写。")
                }

                if let errorMessage = store.errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }

                Section {
                    Button {
                        Task { await store.createDemoSession(using: session) }
                    } label: {
                        if store.isSubmitting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("开始体验")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isSubmitting || store.phone.filter(\.isNumber).count < 6)
                }
            }
            .navigationTitle("欢迎来到 Aim")
            .scrollContentBackground(.hidden)
            .background(Color.aimCanvas)
        }
    }
}

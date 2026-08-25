import SwiftUI

struct OnboardingView: View {
    @Environment(AppSessionStore.self) private var session
    @State private var store = OnboardingStore()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("方式", selection: $store.form.mode) {
                        ForEach(AuthMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("auth-mode-picker")
                }

                if store.form.mode == .register {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("先进入 Aim，孕期信息稍后补充", systemImage: "heart.text.square")
                                .font(.title2.weight(.semibold))
                            Text("预产期不是门槛，准备好后再补充，Aim 才会开始生成对应阶段的计划。")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                }

                Section {
                    TextField("手机号", text: $store.form.phone)
#if os(iOS)
                        .keyboardType(.phonePad)
#endif
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("auth-phone")

                    SecureField("密码", text: $store.form.password)
                        .textContentType(store.form.mode == .register ? .newPassword : .password)
                        .accessibilityIdentifier("auth-password")
                } header: {
                    Text(store.form.mode == .register ? "创建你的账号" : "登录你的账号")
                } footer: {
                    if store.form.mode == .register {
                        Text("密码至少 \(AuthForm.minPasswordLength) 位。不发送短信；忘记密码需要联系管理员重置。")
                    }
                }

                if store.form.mode == .register {
                    Section {
                        // 角色以前写死成妈妈，爸爸和其他家人根本没有入口。
                        Picker("你的身份", selection: $store.form.role) {
                            Text("请选择").tag(FamilyRole?.none)
                            ForEach(FamilyRole.allCases, id: \.self) {
                                Text($0.displayName).tag(FamilyRole?.some($0))
                            }
                        }
                        .accessibilityIdentifier("auth-role")

                        TextField("家里怎么称呼你（选填）", text: $store.form.nickname)
                            .accessibilityIdentifier("auth-nickname")
                    } header: {
                        Text("你在家里是谁")
                    } footer: {
                        Text("孕期属于整个家庭，谁先注册都可以。称呼留空时会显示身份。")
                    }
                }

                if let errorMessage = store.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(Color.aimDanger)
                            .accessibilityIdentifier("auth-error")
                    }
                }

                Section {
                    Button {
                        Task { await store.submit(using: session) }
                    } label: {
                        if store.isSubmitting {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text(store.form.mode == .register ? "注册并进入" : "登录")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isSubmitting || !store.form.canSubmit)
                    .accessibilityIdentifier("auth-submit")
                }
            }
            .navigationTitle("欢迎来到 Aim")
            .scrollContentBackground(.hidden)
            .background(Color.aimCanvas)
        }
    }
}

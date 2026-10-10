import SwiftUI

struct OnboardingView: View {
    @Environment(AppSessionStore.self) private var session
    @State private var store = OnboardingStore()
    @State private var legalPage: LegalPage?

    var body: some View {
        NavigationStack {
            Form {
                if let notice = session.signOutNotice {
                    Section {
                        Text(notice)
                            .font(.subheadline)
                            .foregroundStyle(Color.aimTextSecondary)
                            .accessibilityIdentifier("auth-notice")
                    }
                    .listRowBackground(Color.clear)
                }

                Section {
                    Picker("方式", selection: $store.form.mode) {
                        ForEach(AuthMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("auth-mode-picker")
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

                // 注册就是四个字段，不该拆成两个分组配两个标题。
                // 原来这里还有一张讲预产期的卡片——那是下一屏的事，
                // 在还没有账号的时候说它，只是把表单往下推。
                Section {
                    TextField("手机号", text: $store.form.phone)
#if os(iOS)
                        .keyboardType(.phonePad)
#endif
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("auth-phone")

                    SecureField("密码", text: $store.form.password)
                        // UI 测试下不声明内容类型，免得系统弹「使用强密码」「保存密码」挡住流程。
                        .textContentType(LaunchFlags.isUITesting
                            ? nil : (store.form.mode == .register ? .newPassword : .password))
                        .accessibilityIdentifier("auth-password")

                    if store.form.mode == .register {
                        Picker("你的身份", selection: $store.form.role) {
                            Text("请选择").tag(FamilyRole?.none)
                            ForEach(FamilyRole.allCases, id: \.self) {
                                Text($0.displayName).tag(FamilyRole?.some($0))
                            }
                        }
                        .accessibilityIdentifier("auth-role")

                        // 「留空会显示身份」这句话由占位符本身说清楚了。
                        TextField("称呼（选填）", text: $store.form.nickname)
                            .accessibilityIdentifier("auth-nickname")
                    }
                } footer: {
                    if store.form.mode == .register {
                        // 两件不相干的事：密码约束、身份为什么可以随便选。
                        // 挤成一段就成了流水句，分行让它们各自可读。
                        VStack(alignment: .leading, spacing: 4) {
                            Text("密码至少 \(AuthForm.minPasswordLength) 位，忘记后需联系管理员重置。")
                            Text("孕期属于整个家庭，谁先注册都可以。")
                        }
                    }
                }

                if let errorMessage = store.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(Color.aimDanger)
                            .accessibilityIdentifier("auth-error")
                    }
                }

                if store.form.mode == .register {
                    Section {
                        Toggle(isOn: $store.form.agreedToTerms) {
                            // 两个书名号各自可点；Toggle 的标签区域点击不改变开关状态，
                            // 所以链接按钮放在标签里不会误触。
                            HStack(spacing: 0) {
                                Text("我已阅读并同意")
                                Button("《用户协议》") { legalPage = .terms }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Color.aimAccent)
                                    .accessibilityIdentifier("auth-open-terms")
                                Text("和")
                                Button("《隐私政策》") { legalPage = .privacy }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Color.aimAccent)
                                    .accessibilityIdentifier("auth-open-privacy")
                            }
                            .font(.footnote)
                        }
                        .tint(Color.aimAccent)
                        .accessibilityIdentifier("auth-consent")
                    }
                    .listRowBackground(Color.clear)
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
                .listRowBackground(Color.clear)
            }
            .navigationTitle("欢迎来到 Aim")
            .scrollContentBackground(.hidden)
            .background(Color.aimCanvas)
            .legalPageSheet($legalPage, gateway: session.environment.baseURL)
            .onDisappear { session.signOutNotice = nil }
        }
    }
}

import XCTest
@testable import AimApp

/// AIM 的会话此前只活在内存里，App 一重启就找不回来——对话其实还在 Eve，
/// 只是没有任何入口。会话列表补上这个入口。
final class AgentSessionTitleTests: XCTestCase {
    func testTheTitleIsTheFirstThingYouSaid() {
        XCTAssertEqual(AgentSessionTitle.from("孕期能喝咖啡吗"), "孕期能喝咖啡吗")
    }

    /// 发给模型的文本前面拼了当前页面的上下文（`requestMessage(for:)` 干的），
    /// 那段是给模型看的，不该变成用户看到的标题。
    func testThePageContextPrefixIsStripped() {
        let sent = """
        当前页面：记录
        当前页面摘要：最近有 2 条身体感受记录。

        用户问题：这两天总是恶心怎么办
        """
        XCTAssertEqual(AgentSessionTitle.from(sent), "这两天总是恶心怎么办")
    }

    func testLongQuestionsAreTruncated() {
        let long = String(repeating: "很", count: 100)
        let title = AgentSessionTitle.from(long)
        XCTAssertLessThanOrEqual(title.count, AgentSessionTitle.maxLength)
        XCTAssertTrue(title.hasSuffix("…"), "截断要看得出来是截断，而不是话说了一半")
    }

    func testWhitespaceOnlyInputFallsBackToSomethingReadable() {
        XCTAssertEqual(AgentSessionTitle.from("   \n  "), "新对话")
    }

    /// 多行提问只取第一行做标题——列表里一行放不下第二行。
    func testOnlyTheFirstLineBecomesTheTitle() {
        XCTAssertEqual(AgentSessionTitle.from("能不能吃螃蟹\n顺便问下柿子呢"), "能不能吃螃蟹")
    }
}

@MainActor
final class AgentSessionListTests: XCTestCase {
    private func session(_ title: String, minutesAgo: Int) -> AgentSessionSummary {
        AgentSessionSummary(
            id: UUID(),
            eveSessionID: "wrun_\(title)",
            title: title,
            lastActiveAt: Date().addingTimeInterval(TimeInterval(-60 * minutesAgo))
        )
    }

    /// 打开 AIM 默认接着最近那段，所以「最近」必须是按活跃时间算的。
    func testTheMostRecentSessionIsTheOneToResume() {
        let sessions = [session("旧的", minutesAgo: 600), session("新的", minutesAgo: 5)]
        XCTAssertEqual(AgentSessionSummary.mostRecent(of: sessions)?.title, "新的")
    }

    func testThereIsNothingToResumeWhenTheListIsEmpty() {
        XCTAssertNil(AgentSessionSummary.mostRecent(of: []))
    }
}

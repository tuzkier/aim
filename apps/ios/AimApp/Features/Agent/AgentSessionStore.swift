import Foundation
import Observation

/// AIM 会话列表。
///
/// 只管「有过哪些对话」，不管对话内容——内容留在 Eve，需要时用
/// `eveSessionID` 重放。和 `AgentStore` 分开：那个管的是一段正在进行的对话，
/// 这个管的是所有对话的目录，两者的生命周期和刷新时机都不一样。
@MainActor
@Observable
final class AgentSessionStore {
    var sessions: [AgentSessionSummary] = []
    var isLoading = false
    var errorMessage: String?

    private struct CreateRequest: Encodable {
        let eveSessionID: String
        let title: String

        enum CodingKeys: String, CodingKey {
            case eveSessionID = "eve_session_id"
            case title
        }
    }

    private struct UpdateRequest: Encodable {
        let title: String?
        let touch: Bool
    }

    private struct ListResponse: Decodable {
        let sessions: [AgentSessionSummary]
    }

    func load(environment: APIEnvironment) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let request = environment.businessRequest(path: "/api/v1/agent/sessions")
            let (data, _) = try await URLSession.shared.aimData(for: request)
            sessions = try JSONDecoder.aim.decode(ListResponse.self, from: data).sessions
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 登记一段新对话。失败不打断用户——对话本身已经在进行了，
    /// 列表里少一条比中断提问要好。
    @discardableResult
    func record(
        eveSessionID: String, title: String, environment: APIEnvironment
    ) async -> AgentSessionSummary? {
        do {
            let body = try JSONEncoder.aim.encode(
                CreateRequest(eveSessionID: eveSessionID, title: title))
            let request = environment.businessRequest(
                path: "/api/v1/agent/sessions", method: "POST", body: body)
            let (data, _) = try await URLSession.shared.aimData(for: request)
            let created = try JSONDecoder.aim.decode(AgentSessionSummary.self, from: data)
            sessions.removeAll { $0.id == created.id }
            sessions.insert(created, at: 0)
            return created
        } catch {
            return nil
        }
    }

    /// 回到某段对话继续聊，把它顶到列表最前。
    func touch(_ session: AgentSessionSummary, environment: APIEnvironment) async {
        await patch(session, body: UpdateRequest(title: nil, touch: true), environment: environment)
    }

    func rename(_ session: AgentSessionSummary, to title: String, environment: APIEnvironment) async {
        await patch(session, body: UpdateRequest(title: title, touch: false), environment: environment)
    }

    func delete(_ session: AgentSessionSummary, environment: APIEnvironment) async {
        let previous = sessions
        sessions.removeAll { $0.id == session.id }
        do {
            let request = environment.businessRequest(
                path: "/api/v1/agent/sessions/\(session.id.uuidString)", method: "DELETE")
            _ = try await URLSession.shared.aimData(for: request)
        } catch {
            // 删除失败就把它放回去，而不是让界面显示一个其实还在的会话。
            sessions = previous
            errorMessage = error.localizedDescription
        }
    }

    private func patch(
        _ session: AgentSessionSummary, body: UpdateRequest, environment: APIEnvironment
    ) async {
        do {
            let encoded = try JSONEncoder.aim.encode(body)
            let request = environment.businessRequest(
                path: "/api/v1/agent/sessions/\(session.id.uuidString)",
                method: "PATCH", body: encoded)
            let (data, _) = try await URLSession.shared.aimData(for: request)
            let updated = try JSONDecoder.aim.decode(AgentSessionSummary.self, from: data)
            if let index = sessions.firstIndex(where: { $0.id == updated.id }) {
                sessions[index] = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

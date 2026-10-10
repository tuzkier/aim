import Foundation

struct APIEnvironment: Sendable {
    let baseURL: URL
    let eveBaseURL: URL
    let bearerToken: String?
    let accountID: UUID?
    let familyID: UUID?
    let pregnancyID: UUID?

    func businessRequest(path: String, method: String = "GET", body: Data? = nil) -> URLRequest {
        makeRequest(baseURL: baseURL, path: path, method: method, body: body)
    }

    func eveRequest(path: String, method: String = "GET", body: Data? = nil) -> URLRequest {
        makeRequest(baseURL: eveBaseURL, path: path, method: method, body: body)
    }

    private func makeRequest(baseURL: URL, path: String, method: String, body: Data?) -> URLRequest {
        let url = URL(string: path, relativeTo: baseURL)!
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let bearerToken, !bearerToken.isEmpty {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        if let accountID { request.setValue(accountID.uuidString, forHTTPHeaderField: "x-aim-account-id") }
        if let familyID { request.setValue(familyID.uuidString, forHTTPHeaderField: "x-aim-family-id") }
        if let pregnancyID { request.setValue(pregnancyID.uuidString, forHTTPHeaderField: "x-aim-pregnancy-id") }
        return request
    }
}

enum APIError: LocalizedError, Equatable {
    case invalidResponse
    case http(status: Int, body: String)
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "服务返回了无法识别的结果。"
        case .http(status: 401, _): return "登录已失效，请重新进入。"
        case let .http(status, _): return "请求失败（\(status)），请稍后重试。"
        case .notConfigured: return "请先连接家庭和孕期档案。"
        }
    }

    /// 这张票作废了：账号已不存在，或 token 过期。
    /// 只认 401——403 是「这个账号不能做这件事」，票是好的，不该把人踢下线。
    var isUnauthorized: Bool {
        if case let .http(status, _) = self { return status == 401 }
        return false
    }

    /// 要的东西不存在（比如百科条目已下线）。和其他失败分开：重试也不会好。
    var isNotFound: Bool {
        if case let .http(status, _) = self { return status == 404 }
        return false
    }
}

extension Notification.Name {
    /// 服务端拒绝了当前身份。订阅者应当清掉本地会话，让 App 回到登录页。
    static let aimSessionExpired = Notification.Name("aim.sessionExpired")
}

extension URLSession {
    /// `broadcastsUnauthorized`：401 默认视为票作废并广播 `aimSessionExpired`。
    /// 个别端点用 401 表达别的意思（比如注销时密码不对），调用方传 false 自己处理。
    func aimData(
        for request: URLRequest, broadcastsUnauthorized: Bool = true
    ) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard 200..<300 ~= httpResponse.statusCode else {
            let error = APIError.http(
                status: httpResponse.statusCode, body: String(data: data, encoding: .utf8) ?? ""
            )
            // 在这里广播而不是让每个 store 各自判断：漏掉一处，App 就会抱着废票
            // 卡在空页面上。这是唯一一条所有业务请求都必经的通道。
            if broadcastsUnauthorized, error.isUnauthorized {
                NotificationCenter.default.post(name: .aimSessionExpired, object: nil)
            }
            throw error
        }
        return (data, httpResponse)
    }
}

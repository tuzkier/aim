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
        case let .http(status, _): return "请求失败（\(status)），请稍后重试。"
        case .notConfigured: return "请先连接家庭和孕期档案。"
        }
    }
}

extension URLSession {
    func aimData(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw APIError.http(status: httpResponse.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return (data, httpResponse)
    }
}

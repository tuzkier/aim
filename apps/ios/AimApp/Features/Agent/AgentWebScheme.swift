import Foundation
import WebKit

/// 对话面 WebView 的自定义 scheme。
///
/// 页面是从 App bundle 里加载的。如果直接用 `file://`，页面里对 `/eve/v1/*` 的
/// 相对请求会解析成 `file:///eve/v1/...` 而失败；改成绝对地址又要给 Eve 配 CORS，
/// 而 `file://` 的 origin 是 `null`，配起来只能全放开。
///
/// 所以静态资源和后端请求统一走这一个 scheme：页面看到的是同源，
/// 转发由原生做。外壳因此也能离线加载，不至于断网就白屏。
enum AgentWebScheme {
    static let name = "aim-app"
    static let host = "agent"

    static var indexURL: URL {
        URL(string: "\(name)://\(host)/index.html")!
    }
}

/// 把 `aim-app://` 的请求分成两类：bundle 里的静态资源，和转发给后端的 API。
///
/// - Warning: 事件流是 NDJSON 长连接，必须边收边转（`didReceive(data:)` 多次调用），
///   不能等整个响应结束再一次性给——那样界面会一直空着直到一轮结束，
///   流式输出就白做了。
final class AgentWebSchemeHandler: NSObject, WKURLSchemeHandler {
    private let apiBaseURL: URL
    private let eveBaseURL: URL
    private let bundle: Bundle
    private let session: URLSession
    /// 每个进行中的请求对应一个上游任务，stop 时要能取消。
    private var tasks: [ObjectIdentifier: URLSessionTask] = [:]
    private let lock = NSLock()

    init(apiBaseURL: URL, eveBaseURL: URL, bundle: Bundle = .main) {
        self.apiBaseURL = apiBaseURL
        self.eveBaseURL = eveBaseURL
        self.bundle = bundle
        // 事件流没有固定时长，按响应间隔算超时而不是总时长，
        // 否则一轮长回答会被拦腰掐断。
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 3600
        self.session = URLSession(configuration: configuration)
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, let path = normalizedPath(of: url) else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        if path.hasPrefix("/eve/") {
            forward(urlSchemeTask, to: eveBaseURL, path: path, query: url.query)
        } else if path.hasPrefix("/api/") {
            forward(urlSchemeTask, to: apiBaseURL, path: path, query: url.query)
        } else {
            serveBundledAsset(urlSchemeTask, path: path)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        let key = ObjectIdentifier(urlSchemeTask)
        lock.lock()
        let task = tasks.removeValue(forKey: key)
        lock.unlock()
        task?.cancel()
    }

    private func isLive(_ urlSchemeTask: any WKURLSchemeTask) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return tasks[ObjectIdentifier(urlSchemeTask)] != nil
    }

    private func normalizedPath(of url: URL) -> String? {
        let path = url.path
        return path.isEmpty || path == "/" ? "/index.html" : path
    }

    // MARK: - 静态资源

    private func serveBundledAsset(_ urlSchemeTask: any WKURLSchemeTask, path: String) {
        // 只从打包进来的那个目录里取，且不接受路径穿越。
        let relative = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard !relative.contains(".."),
              let root = bundle.url(forResource: "AgentWeb", withExtension: nil)
        else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let fileURL = root.appendingPathComponent(relative)
        guard fileURL.path.hasPrefix(root.path), let data = try? Data(contentsOf: fileURL) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        let response = HTTPURLResponse(
            url: urlSchemeTask.request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": mimeType(for: fileURL.pathExtension)]
        )!
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    private func mimeType(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "html": "text/html; charset=utf-8"
        case "js", "mjs": "text/javascript; charset=utf-8"
        case "css": "text/css; charset=utf-8"
        case "json": "application/json; charset=utf-8"
        case "svg": "image/svg+xml"
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "woff2": "font/woff2"
        default: "application/octet-stream"
        }
    }

    // MARK: - 转发

    private func forward(
        _ urlSchemeTask: any WKURLSchemeTask,
        to base: URL,
        path: String,
        query: String?
    ) {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        components.path = path
        components.query = query
        guard let target = components.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        var request = URLRequest(url: target)
        request.httpMethod = urlSchemeTask.request.httpMethod
        request.httpBody = urlSchemeTask.request.httpBody
        for (field, value) in urlSchemeTask.request.allHTTPHeaderFields ?? [:] {
            request.setValue(value, forHTTPHeaderField: field)
        }

        let delegate = StreamingForwarder(urlSchemeTask: urlSchemeTask) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.tasks.removeValue(forKey: ObjectIdentifier(urlSchemeTask))
            self.lock.unlock()
        }
        // 单独一个 session：URLSessionDataDelegate 要按任务分发增量数据，
        // 共用 session 的话得自己维护 task -> delegate 的映射，没必要。
        let streamingSession = URLSession(
            configuration: session.configuration, delegate: delegate, delegateQueue: nil
        )
        let task = streamingSession.dataTask(with: request)

        lock.lock()
        tasks[ObjectIdentifier(urlSchemeTask)] = task
        lock.unlock()

        task.resume()
    }
}

/// 把上游响应边收边交给 WebView。
///
/// 事件流是长连接，等 `completionHandler` 再一次性给的话，流式输出就退化成
/// 「一轮结束才整段出现」——那正是我们这次要修掉的观感。
private final class StreamingForwarder: NSObject, URLSessionDataDelegate {
    private let urlSchemeTask: any WKURLSchemeTask
    private let onFinish: () -> Void
    /// WKURLSchemeTask 在 stop 之后再调用会崩，用它挡住迟到的回调。
    private var finished = false
    private let lock = NSLock()

    init(urlSchemeTask: any WKURLSchemeTask, onFinish: @escaping () -> Void) {
        self.urlSchemeTask = urlSchemeTask
        self.onFinish = onFinish
    }

    private func guarded(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        body()
    }

    private func finish(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        body()
        onFinish()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guarded { urlSchemeTask.didReceive(response) }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guarded { urlSchemeTask.didReceive(data) }
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?
    ) {
        finish {
            if let error, (error as? URLError)?.code != .cancelled {
                urlSchemeTask.didFailWithError(error)
            } else if error == nil {
                urlSchemeTask.didFinish()
            }
        }
        session.finishTasksAndInvalidate()
    }
}

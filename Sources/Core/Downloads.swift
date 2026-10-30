import Foundation

struct DownloadRecord: Codable {
    enum State: String, Codable {
        case downloading, done, failed
    }

    let id: String
    let ref: MediaRef
    let videoId: String
    let label: String?
    let sourceURL: String
    let headers: [String: String]
    let createdAt: Date
    var fileName: String?
    var state: State
    var progress: Double
    var totalBytes: Int64
    var errorMessage: String?

    var localURL: URL? { fileName.map { DownloadManager.directory.appendingPathComponent($0) } }

    var title: String { label.map { "\(ref.name) · \($0)" } ?? ref.name }
}

/// Background downloads of direct HTTP streams, kept in Documents/Downloads
/// (also visible in the Files app).
final class DownloadManager: NSObject, URLSessionDownloadDelegate {
    static let shared = DownloadManager()
    static let sessionIdentifier = "com.codeymoore.lumen.downloads"

    static let directory: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private(set) var records: [DownloadRecord] = []
    var backgroundCompletionHandler: (() -> Void)?
    private var lastNotify = Date.distantPast
    private let storageKey = "lumen.downloads.v1"

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: DownloadManager.sessionIdentifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: self, delegateQueue: OperationQueue.main)
    }()

    private override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([DownloadRecord].self, from: data) {
            records = saved
        }
    }

    private func save(notify: Bool = true) {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        if notify { NotificationCenter.default.post(name: .downloadsChanged, object: nil) }
    }

    /// Reattaches to the background session on launch and fails downloads that no longer exist.
    func reconnect() {
        session.getTasksWithCompletionHandler { [weak self] _, _, downloads in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let live = Set(downloads.compactMap { $0.taskDescription })
                var changed = false
                for i in self.records.indices where self.records[i].state == .downloading && !live.contains(self.records[i].id) {
                    self.records[i].state = .failed
                    self.records[i].errorMessage = "Interrupted"
                    changed = true
                }
                if changed { self.save() }
            }
        }
    }

    func record(for videoId: String) -> DownloadRecord? {
        records.first { $0.videoId == videoId && $0.state != .failed }
    }

    func start(ref: MediaRef, videoId: String, label: String?, url: URL, headers: [String: String]) {
        let record = DownloadRecord(id: UUID().uuidString, ref: ref, videoId: videoId, label: label,
                                    sourceURL: url.absoluteString, headers: headers, createdAt: Date(),
                                    fileName: nil, state: .downloading, progress: 0, totalBytes: 0, errorMessage: nil)
        records.insert(record, at: 0)
        begin(record)
        save()
    }

    private func begin(_ record: DownloadRecord) {
        guard let url = URL(string: record.sourceURL) else { return }
        var request = URLRequest(url: url)
        for (k, v) in record.headers { request.setValue(v, forHTTPHeaderField: k) }
        let task = session.downloadTask(with: request)
        task.taskDescription = record.id
        task.resume()
    }

    func retry(_ id: String) {
        guard let i = records.firstIndex(where: { $0.id == id }) else { return }
        records[i].state = .downloading
        records[i].progress = 0
        records[i].errorMessage = nil
        begin(records[i])
        save()
    }

    func delete(_ id: String) {
        session.getTasksWithCompletionHandler { _, _, downloads in
            downloads.filter { $0.taskDescription == id }.forEach { $0.cancel() }
        }
        if let i = records.firstIndex(where: { $0.id == id }) {
            if let file = records[i].localURL { try? FileManager.default.removeItem(at: file) }
            records.remove(at: i)
        }
        save()
    }

    // MARK: URLSessionDownloadDelegate (delivered on the main queue)

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription, let i = records.firstIndex(where: { $0.id == id }) else { return }
        records[i].totalBytes = totalBytesExpectedToWrite
        records[i].progress = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
        if Date().timeIntervalSince(lastNotify) > 0.5 {
            lastNotify = Date()
            save()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription, let i = records.firstIndex(where: { $0.id == id }) else { return }
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            records[i].state = .failed
            records[i].errorMessage = "Server error \(http.statusCode)"
            save()
            return
        }
        var ext = (downloadTask.response?.suggestedFilename as NSString?)?.pathExtension ?? ""
        if ext.isEmpty { ext = (URL(string: records[i].sourceURL)?.pathExtension) ?? "" }
        if ext.isEmpty || ext.count > 5 { ext = "mp4" }
        let name = "\(id).\(ext)"
        let dest = DownloadManager.directory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.moveItem(at: location, to: dest)
            records[i].fileName = name
            records[i].state = .done
            records[i].progress = 1
        } catch {
            records[i].state = .failed
            records[i].errorMessage = "Couldn't save the file"
        }
        save()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error, let id = task.taskDescription,
              let i = records.firstIndex(where: { $0.id == id }), records[i].state == .downloading else { return }
        if (error as NSError).code == NSURLErrorCancelled { return }
        records[i].state = .failed
        records[i].errorMessage = error.localizedDescription
        save()
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        backgroundCompletionHandler?()
        backgroundCompletionHandler = nil
    }
}

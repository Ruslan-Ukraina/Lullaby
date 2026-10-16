// The network side of the engine updater, behind a protocol so tests can serve
// a fake release, cut a download short or take the network away.

import Foundation

protocol EngineTransport: Sendable {
    /// A small file in full (manifest, signature). Anything but HTTP 200 throws.
    func fetch(_ url: URL, limit: Int) async throws -> Data

    /// Fetches `url` into `part`, continuing from the bytes already there with an
    /// HTTP Range request. `progress` gets the size of `part` as it grows. Throws
    /// when the transfer stops early; what arrived stays in `part` for next time.
    func download(_ url: URL, to part: URL, progress: @escaping @Sendable (Int64) -> Void) async throws

    /// The same for a file whose size is known: several ranges at once where the
    /// server allows it (SegmentedDownload). `part` ends up the same either way.
    func download(
        _ url: URL, to part: URL, size: Int64, progress: @escaping @Sendable (Int64) -> Void
    ) async throws
}

extension EngineTransport {
    func download(
        _ url: URL, to part: URL, size: Int64, progress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        try await download(url, to: part, progress: progress)
    }
}

struct TransportFailure: LocalizedError, Equatable {
    let detail: String
    /// The HTTP status, when the server answered with one other than 200.
    var status: Int? = nil
    var errorDescription: String? { detail }
}

/// URLSession, one session per transfer, data written to disk as it arrives.
/// Requests may carry headers (the private release mode, ReleaseAccess.swift); a
/// redirect to another host drops Authorization (RedirectPolicy).
struct URLSessionEngineTransport: EngineTransport, RequestTransport {

    func fetch(_ url: URL, limit: Int) async throws -> Data {
        try await fetch(URLRequest(url: url), limit: limit)
    }

    func fetch(_ original: URLRequest, limit: Int) async throws -> Data {
        var request = original
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if request.timeoutInterval == 60 { request.timeoutInterval = 30 }
        let name = request.url?.lastPathComponent ?? "the file"
        let (data, response) = try await URLSession.shared.data(for: request, delegate: RedirectGuard())
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw TransportFailure(detail: "\(name): the server answered \(http.statusCode).", status: http.statusCode)
        }
        guard data.count <= limit else {
            throw TransportFailure(detail: "\(name) is larger than expected.")
        }
        return data
    }

    func download(_ url: URL, to part: URL, progress: @escaping @Sendable (Int64) -> Void) async throws {
        try await download(URLRequest(url: url), to: part, progress: progress)
    }

    func download(
        _ url: URL, to part: URL, size: Int64, progress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        let pieces = SegmentedDownload.piecesDirectory(for: part)
        do {
            try await SegmentedDownload().run(part: part, total: size, fetch: { range, file, grew in
                try await self.fetchRange(URLRequest(url: url), range: range, into: file, progress: grew)
            }, progress: progress)
        } catch is RangeUnsupported {
            AppLog.note("download: \(url.lastPathComponent): the server ignores ranges, one stream instead")
            try? FileManager.default.removeItem(at: pieces)
            try await download(URLRequest(url: url), to: part, progress: progress)
        }
    }

    /// Bytes `range` appended to `file` (one piece of a SegmentedDownload).
    func fetchRange(
        _ original: URLRequest, range: ClosedRange<Int64>, into file: URL,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        var request = original
        request.setValue("bytes=\(range.lowerBound)-\(range.upperBound)", forHTTPHeaderField: "Range")
        try await transfer(request, to: file, ranged: true, progress: progress)
    }

    func download(_ original: URLRequest, to part: URL, progress: @escaping @Sendable (Int64) -> Void) async throws {
        try await transfer(original, to: part, ranged: false, progress: progress)
    }

    /// `ranged`: the request carries its own Range and only 206 is accepted; otherwise
    /// the file continues from its end, and a 200 starts it over.
    private func transfer(
        _ original: URLRequest, to part: URL, ranged: Bool, progress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: part.path(percentEncoded: false)) {
            fm.createFile(atPath: part.path(percentEncoded: false), contents: nil)
        }
        let handle = try FileHandle(forWritingTo: part)
        defer { try? handle.close() }
        let offset = try handle.seekToEnd()

        var request = original
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 60
        if !ranged, offset > 0 { request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") }

        let receiver = Receiver(handle: handle, offset: Int64(offset), ranged: ranged, progress: progress)
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: .ephemeral, delegate: receiver, delegateQueue: queue)
        defer { session.finishTasksAndInvalidate() }
        let task = session.dataTask(with: request)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                receiver.continuation = continuation
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    /// Runs on the session's serial queue only.
    private final class Receiver: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        let handle: FileHandle
        var written: Int64
        let ranged: Bool
        let progress: @Sendable (Int64) -> Void
        var continuation: CheckedContinuation<Void, Error>?
        var failure: Error?

        init(handle: FileHandle, offset: Int64, ranged: Bool, progress: @escaping @Sendable (Int64) -> Void) {
            self.handle = handle
            self.written = offset
            self.ranged = ranged
            self.progress = progress
        }

        func urlSession(
            _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
            completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
        ) {
            // A file: URL (a local test feed) has no HTTP status; it is the whole file.
            let status = (response as? HTTPURLResponse)?.statusCode ?? (response.url?.isFileURL == true ? 200 : 0)
            if ranged {
                if status == 206 {
                    completionHandler(.allow)
                } else {
                    failure = status == 200
                        ? RangeUnsupported() : TransportFailure(detail: "The download server answered \(status).", status: status)
                    completionHandler(.cancel)
                }
                return
            }
            switch status {
            case 206 where written > 0:
                AppLog.note("engine: server resumed the download at byte \(written) (206)")
                completionHandler(.allow)
            case 200:
                // The server sent the whole file: start the part over.
                if written > 0 { AppLog.note("engine: server ignored the range, starting over (200)") }
                do {
                    try handle.truncate(atOffset: 0)
                    written = 0
                    completionHandler(.allow)
                } catch {
                    failure = error
                    completionHandler(.cancel)
                }
            case 416 where written > 0:
                // Nothing past what is on disk: the part is complete (or too long,
                // which the size check after the download catches).
                completionHandler(.cancel)
            default:
                failure = TransportFailure(detail: "The download server answered \(status).", status: status)
                completionHandler(.cancel)
            }
        }

        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(RedirectPolicy.follow(request, from: task.originalRequest))
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            do {
                try handle.write(contentsOf: data)
                written += Int64(data.count)
                progress(written)
            } catch {
                failure = error
                dataTask.cancel()
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            let status = (task.response as? HTTPURLResponse)?.statusCode
            if let failure {
                continuation?.resume(throwing: failure)
            } else if status == 416, !ranged {
                continuation?.resume()
            } else if let error {
                continuation?.resume(throwing: error)
            } else {
                continuation?.resume()
            }
            continuation = nil
        }
    }
}

/// RedirectPolicy for URLSession's one-shot requests.
private final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        RedirectPolicy.follow(request, from: task.originalRequest)
    }
}

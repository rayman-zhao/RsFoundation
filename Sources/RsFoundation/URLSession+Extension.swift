import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// One-shot HTTP request helpers with status-code checking, failure logging, and a response payload that
/// carries either the response body or the error description.
extension URLSession {
    /// Sends a GET request.
    ///
    /// - Parameters:
    ///   - urlString: The URL to request.
    ///   - timeout: The timeout interval of the request; `nil` keeps the session default.
    /// - Returns: Whether the server responded with a 2xx status, and the response body — or, on failure, the
    ///   error response body if any, otherwise the error description.
    @discardableResult
    public func get(urlString: String, timeout: TimeInterval? = nil) async -> (
        success: Bool, data: Data
    ) {
        do {
            guard let url = URL(string: urlString) else { throw URLError(.badURL) }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            if let timeout { request.timeoutInterval = timeout }

            let (data, response) = try await data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                200...299 ~= httpResponse.statusCode
            else {
                log.error(
                    "GET request failed: \(url), \nstatus: \(response), \nresponse: \(String(data: data, encoding: .utf8) ?? "")"
                )
                return (false, data)
            }

            return (true, data)
        } catch {
            log.error("GET request error: \(urlString), error: \(error)")
            let errorData = String(describing: error).data(using: .utf8) ?? Data()
            return (false, errorData)
        }
    }

    /// Sends a PUT request with a JSON-encoded body.
    ///
    /// - Parameters:
    ///   - urlString: The URL to request.
    ///   - body: The Encodable object encoded as the JSON request body.
    /// - Returns: Whether the server responded with a 2xx status, and the response body — or, on failure, the
    ///   error response body if any, otherwise the error description.
    @discardableResult
    public func put(urlString: String, body: some Encodable) async -> (
        success: Bool, data: Data
    ) {
        // Encode before awaiting: the Encodable body is not necessarily Sendable and must not be captured
        // across a suspension.
        let bodyData: Data?
        do {
            bodyData = try JSONEncoder().encode(body)
        } catch {
            log.error("PUT request error: \(urlString), error: \(error)\nRequest body: \(body)")
            let errorData = String(describing: error).data(using: .utf8) ?? Data()
            return (false, errorData)
        }

        return await put(urlString: urlString, bodyData: bodyData)
    }

    /// Sends a PUT request with the given JSON data as the body; `nil` body data reports an encoding failure.
    func put(
        urlString: String, bodyData: Data?
    ) async -> (success: Bool, data: Data) {
        guard let bodyData else {
            log.error("Error: failed to encode the request body")
            return (false, Data())
        }

        do {
            guard let url = URL(string: urlString) else { throw URLError(.badURL) }
            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = bodyData

            let (data, response) = try await data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                200...299 ~= httpResponse.statusCode
            else {
                let responseText = String(data: data, encoding: .utf8) ?? ""
                let bodyText = String(data: bodyData, encoding: .utf8) ?? ""
                log.error(
                    "PUT request failed: \(url), \nstatus: \(response), \nresponse: \(responseText), \nrequest body: \(bodyText)"
                )
                return (false, data)
            }

            return (true, data)
        } catch {
            log.error("PUT request error: \(urlString), error: \(error)")
            let errorData = String(describing: error).data(using: .utf8) ?? Data()
            return (false, errorData)
        }
    }

    /// Sends a DELETE request.
    ///
    /// - Parameter urlString: The URL to request.
    /// - Returns: Whether the server responded with a 2xx status, and the response body — or, on failure, the
    ///   error response body if any, otherwise the error description.
    @discardableResult
    public func delete(urlString: String) async -> (success: Bool, data: Data) {
        do {
            guard let url = URL(string: urlString) else { throw URLError(.badURL) }
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"

            let (data, response) = try await data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                200...299 ~= httpResponse.statusCode
            else {
                log.error(
                    "DELETE request failed: \(url), \nstatus: \(response), \nresponse: \(String(data: data, encoding: .utf8) ?? "")"
                )
                return (false, data)
            }

            return (true, data)
        } catch {
            log.error("DELETE request error: \(urlString), error: \(error)")
            if let errorData = String(describing: error).data(using: .utf8) {
                return (false, errorData)
            }
            return (false, Data())
        }
    }

    /// Sends a GET request and delivers the result on the main actor.
    ///
    /// - Parameters:
    ///   - urlString: The URL to request.
    ///   - onCompleted: The handler called on the main actor with whether the request succeeded and the
    ///     response body, which carries the error response body or error description on failure.
    public func get(
        urlString: String, onCompleted: @escaping @MainActor @Sendable (Bool, Data) -> Void
    ) {
        Task {
            let (success, data) = await get(urlString: urlString)
            await MainActor.run { onCompleted(success, data) }
        }
    }

    public enum DownloadResult {
        case success(url: URL)
        case networkFailure(detail: String)
        case fileFailure(detail: String)
    }
    public func download(
        urlString: String, saveUrl: URL,
        onCompleted: @escaping @MainActor (DownloadResult) -> Void
    ) {
        Task {
            let (success, data) = await get(urlString: urlString)

            let result: DownloadResult
            if success {
                do {
                    try data.write(to: saveUrl)
                    result = .success(url: saveUrl)
                } catch {
                    result = .fileFailure(detail: String(describing: error))
                }
            } else {
                result = .networkFailure(detail: String(data: data, encoding: .utf8) ?? "")
            }

            await MainActor.run { onCompleted(result) }
        }
    }

    /// Sends a PUT request with a JSON-encoded body and delivers the result on the main actor.
    ///
    /// - Parameters:
    ///   - urlString: The URL to request.
    ///   - body: The Encodable object encoded as the JSON request body.
    ///   - onCompleted: The handler called on the main actor with whether the request succeeded and the
    ///     response body, which carries the error response body or error description on failure.
    public func put(
        urlString: String, body: some Encodable, minDuration: TimeInterval? = 0.5,
        onCompleted: @escaping @MainActor @Sendable (Bool, Data) -> Void
    ) {
        // Encode before entering the task: the Encodable body is not necessarily Sendable and must not be
        // captured by the task closure.
        let bodyData: Data?
        do {
            bodyData = try JSONEncoder().encode(body)
        } catch {
            log.error("PUT request error: \(urlString), error: \(error)\nRequest body: \(body)")
            bodyData = nil
        }

        Task {
            let startedAt = DispatchTime.now().uptimeNanoseconds

            let (success, data) = await put(urlString: urlString, bodyData: bodyData)

            let elapsed = DispatchTime.now().uptimeNanoseconds - startedAt
            if let minDuration {
                let duration: UInt64 = UInt64(minDuration * 1_000_000)
                if duration > elapsed {
                    try? await Task.sleep(nanoseconds: duration - elapsed)
                }
            }

            await MainActor.run { onCompleted(success, data) }
        }
    }

    /// Sends a DELETE request and delivers the result on the main actor.
    ///
    /// - Parameters:
    ///   - urlString: The URL to request.
    ///   - onCompleted: The handler called on the main actor with whether the request succeeded and the
    ///     response body, which carries the error response body or error description on failure.
    public func delete(
        urlString: String, onCompleted: @escaping @MainActor @Sendable (Bool, Data) -> Void
    ) {
        Task {
            let (success, data) = await delete(urlString: urlString)
            await MainActor.run { onCompleted(success, data) }
        }
    }
}

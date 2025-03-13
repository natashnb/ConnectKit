//
//  HTTPLoader.swift
//  NetworkLoader
//
//  Created by Natash Bangera on 19/07/24.
//

import Foundation

/// Template class used to load an ``HTTPRequest``. Can be used in a chain to modify requests, the terminal loader is
// responsible for making the network call (if needed) and returning an ``HTTPResult``.
/// Subclasses must implement cancellation handling as required.
open class HTTPLoader {

    public var nextLoader: HTTPLoader? {
        willSet {
            guard nextLoader == nil else { fatalError("The nextLoader may only be set once") }
        }
    }

    public init() {}

    open func load(request: HTTPRequest) async -> HTTPResult {

        if Task.isCancelled {
            return .failure(HTTPError(code: .cancelled, request: request))
        }

        if let next = nextLoader {
            return await next.load(request: request)
        } else {
            let error = HTTPError(code: .cannotConnect, request: request)
            return .failure(error)
        }
    }
}

#if DEBUG
    import os.log
    /// Use this to log requests to the console. Only available in debug mode to avoid leaking sensitive data.
    public class PrintLoader: HTTPLoader {

        private let log: Logger

        public init(logger: Logger) {
            log = logger
        }

        override public func load(request: HTTPRequest) async -> HTTPResult {

            log.log("LOADING REQUEST\n\(request)")
            let result = await super.load(request: request)
            log.log("RECEIVED RESULT:\n\(result)\n")
            return result
        }
    }
#endif

// /// Custom operator to allow easier loader chain setup
// precedencegroup LoaderChainingPrecedence {
//    higherThan: NilCoalescingPrecedence
//    associativity: right
// }
//
// infix operator --> : LoaderChainingPrecedence
//
// @discardableResult
// public func --> (lhs: HTTPLoader?, rhs: HTTPLoader?) -> HTTPLoader? {
//    lhs?.nextLoader = rhs
//    return lhs ?? rhs
// }

/// Use waitsForConnectivity in the session passed to this
public class URLSessionLoader: HTTPLoader {

    let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
        super.init()
    }

    override public func load(request: HTTPRequest) async -> HTTPResult {

        do {
            if let body = request.body as? MultipartFormBody {
                var urlRequest = try request.getFileUploadURLRequest()
                urlRequest.networkServiceType = .responsiveData
                urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
                let fileURL = try await body.writeToFile()
                urlRequest.setValue("keep-alive", forHTTPHeaderField: "Connection")
                urlRequest.setValue("300", forHTTPHeaderField: "Keep-Alive")
                if let size = FileManager.default.sizeOfFile(at: fileURL) {
                    urlRequest.setValue(String(size), forHTTPHeaderField: "Content-Length")
                }
                let (data, response) = try await session.upload(for: urlRequest, fromFile: fileURL)
                return HTTPResult(request: request, responseData: data, response: response, error: nil)
            } else {
                let urlRequest = try request.getURLRequest()
                let (data, response) = try await session.data(for: urlRequest)
                return HTTPResult(request: request, responseData: data, response: response, error: nil)
            }
        } catch let error as HTTPError {
            return .failure(error)
        } catch let error as URLError where error.code == .cancelled {
            return .failure(.init(code: .cancelled, request: request, response: nil, underlyingError: error))
        } catch {
            // something went wrong creating the body; stop and report back
            return .failure(.init(code: .invalidRequest, request: request, response: nil, underlyingError: error))
        }
    }
}

private extension FileManager {
    func sizeOfFile(at url: URL) -> Int64? {
        guard let attrs = try? attributesOfItem(atPath: url.relativePath) else {
            return nil
        }

        return attrs[.size] as? Int64
    }
}

/// Use to modify an HTTPRequest with a passed in closure.
public class ModifyRequest: HTTPLoader {

    private let modifier: (HTTPRequest) -> HTTPRequest

    public init(modifier: @escaping (HTTPRequest) -> HTTPRequest) {
        self.modifier = modifier
        super.init()
    }

    override public func load(request: HTTPRequest) async -> HTTPResult {
        let modifiedRequest = modifier(request)
        return await super.load(request: modifiedRequest)
    }
}

/// Use with an array of closures that respond with appropriate mock responses for each request.
public class MockLoader: HTTPLoader {

    //    public typealias HTTPHandler = (HTTPResult) -> Void
    public typealias MockHandler = (HTTPRequest) async throws -> HTTPResult

    private var nextHandlers = [MockHandler]()

    override public func load(request: HTTPRequest) async -> HTTPResult {

        if nextHandlers.isEmpty == false {
            let next = nextHandlers.removeFirst()
            do {
                return try await next(request)
            } catch {
                return .failure(HTTPError(
                    code: .invalidResponse,
                    request: request,
                    response: nil,
                    underlyingError: error
                ))
            }
        } else {
            let error = HTTPError(code: .cannotConnect, request: request)
            return .failure(error)
        }
    }

    @discardableResult
    public func setNextMock(_ handler: @escaping MockHandler) -> MockLoader {
        nextHandlers.append(handler)
        return self
    }
}

/// Use this loader to automatically retry requests in the chain on error.
public class RetryLoader: HTTPLoader {

    public let maxRetryCount: Int

    public init(maxRetryCount: Int = 1) {
        self.maxRetryCount = maxRetryCount
    }

    override public func load(request: HTTPRequest) async -> HTTPResult {

        let result = await super.load(request: request)

        guard
            let response = result.response,
            !(200 ..< 300 ~= response.status.rawValue)
        else {
            return result
        }

        var request = result.request

        if request.canRetry, request.retryCount < maxRetryCount {
            request.retryCount += 1
            return await load(request: request)
        } else {
            return result
        }
    }
}

//
//  HTTPRequest.swift
//  NetworkLoader
//
//  Created by Natash Bangera on 19/07/24.
//

import Foundation

/// Protocol used to define custom, ad-hoc options on HTTPRequests.
public protocol HTTPRequestOption: Sendable {
    associatedtype Value: Sendable

    /// The value to use if a request does not provide a customized value
    static var defaultOptionValue: Value { get }
}

public struct HTTPRequest: Sendable {

    let identifier = UUID()

    private var urlComponents = URLComponents()
    public var method: Method = .get
    public var headers: [String: String] = [:]
    public var body: HTTPBody = EmptyBody()
    public var canRetry: Bool = false
    public var retryCount: UInt8 = 0

    private var options = [ObjectIdentifier: any Sendable]()

    public init() {
        urlComponents.scheme = "https"
    }

    public var url: URL? {
        urlComponents.url
    }
}

public extension HTTPRequest {
    init(
        method: HTTPRequest.Method = .get,
        headers: [String: String] = [:],
        host: String? = nil,
        path: String,
        queryItems: [URLQueryItem]? = nil,
        params: [String: any Sendable]? = nil,
        canRetry: Bool = false,
        authMethod: HTTPAuthMethod = .userAuth
    ) {
        self.init()
        self.method = method
        self.headers = headers
        self.host = host
        self.path = path
        urlComponents.queryItems = queryItems
        self.canRetry = canRetry
        self.authMethod = authMethod

        if let params {
            body = JSONBody(params)
        }
    }
}

public extension HTTPRequest {
    init(
        method: HTTPRequest.Method = .get,
        headers: [String: String] = [:],
        urlComponents: URLComponents,
        params: [String: any Sendable]? = nil,
        canRetry: Bool = true,
        authMethod: HTTPAuthMethod = .userAuth
    ) {
        self.urlComponents = urlComponents
        self.method = method
        self.headers = headers
        host = host
        path = path
        self.urlComponents.queryItems = queryItems
        self.canRetry = canRetry
        self.authMethod = authMethod

        if let params {
            body = JSONBody(params)
        }
    }
}

extension HTTPRequest {
    /// Create a GET request
    public static func get(
        path: String,
        host: String? = nil,
        queryItems: [URLQueryItem]? = nil,
        headers: [String: String] = [:]
    ) -> HTTPRequest {
        HTTPRequest(
            method: .get,
            headers: headers,
            host: host,
            path: path,
            queryItems: queryItems
        )
    }

    /// Create a POST request with JSON body
    public static func post<T: Sendable & Encodable>(
        path: String,
        host: String? = nil,
        body: T,
        headers: [String: String] = [:]
    ) -> HTTPRequest {
        var request = HTTPRequest(
            method: .post,
            headers: headers,
            host: host,
            path: path
        )
        request.body = JSONEncodableBody(
            body
        )
        return request
    }

    /// Create a multipart form request
    public static func multipartFormPost(
        path: String,
        host: String? = nil,
        formContent: [MultipartFormBody.Content],
        headers: [String: String] = [:]
    ) -> HTTPRequest {
        var request = HTTPRequest(
            method: .post,
            headers: headers,
            host: host,
            path: path
        )
        request.body = MultipartFormBody(
            values: formContent
        )
        return request
    }
}

public extension HTTPRequest {

    enum Method: String, Sendable {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case delete = "DELETE"
        case patch = "PATCH"
    }
}

public extension HTTPRequest {

    var scheme: String { urlComponents.scheme ?? "https" }

    var host: String? {
        get { urlComponents.host }
        set { urlComponents.host = newValue }
    }

    var path: String {
        get { urlComponents.path }
        set { urlComponents.path = newValue }
    }

    var queryItems: [URLQueryItem]? {
        get { urlComponents.queryItems }
        set { urlComponents.queryItems = newValue }
    }

    var port: Int? {
        get { urlComponents.port }
        set { urlComponents.port = newValue }
    }
}

public extension HTTPRequest {

    func getURLRequest() throws -> URLRequest {

        guard let url else {
            // we couldn't construct a proper URL out of the request's URLComponents
            throw HTTPError(code: .invalidRequest, request: self, response: nil, underlyingError: nil)
        }
        // construct the URLRequest
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method.rawValue

        // copy over any custom HTTP headers
        for (header, value) in headers {
            urlRequest.addValue(value, forHTTPHeaderField: header)
        }

        if body.isEmpty == false {
            // if our body defines additional headers, add them
            for (header, value) in body.additionalHeaders {
                urlRequest.addValue(value, forHTTPHeaderField: header)
            }

            // attempt to retrieve the body data
            do {
                urlRequest.httpBody = try body.encode()
            } catch {
                // something went wrong creating the body; stop and report back
                throw HTTPError(code: .invalidRequest, request: self, response: nil, underlyingError: error)
            }
        }

        return urlRequest
    }

    func getFileUploadURLRequest() throws -> URLRequest {

        guard let url else {
            // we couldn't construct a proper URL out of the request's URLComponents
            throw HTTPError(code: .invalidRequest, request: self, response: nil, underlyingError: nil)
        }
        // construct the URLRequest
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method.rawValue

        // copy over any custom HTTP headers
        for (header, value) in headers {
            urlRequest.addValue(value, forHTTPHeaderField: header)
        }

        if body.isEmpty == false {
            // if our body defines additional headers, add them
            for (header, value) in body.additionalHeaders {
                urlRequest.addValue(value, forHTTPHeaderField: header)
            }

            // Do not encode body
        }

        return urlRequest
    }
}

public extension HTTPRequest {
    subscript<O: HTTPRequestOption>(option type: O.Type) -> O.Value {
        get {
            // create the unique identifier for this type as our lookup key
            let id = ObjectIdentifier(type)

            // pull out any specified value from the options dictionary, if it's the right type
            // if it's missing or the wrong type, return the defaultOptionValue
            guard let value = options[id] as? O.Value else { return type.defaultOptionValue }

            // return the value from the options dictionary
            return value
        }
        set {
            let id = ObjectIdentifier(type)
            // save the specified value into the options dictionary
            options[id] = newValue
        }
    }
}

extension HTTPRequest: CustomStringConvertible {
    public var description: String {
        debugDescription
    }
}

extension HTTPRequest: CustomDebugStringConvertible {

    public var debugDescription: String {
        """
        ++++++++++++++++++++++++++++++++
        <\(identifier)> [REQUEST] \(method.rawValue.uppercased()) \(url?.absoluteString ?? "")

        -------------HEADERS-------------
        \(headers.reduce("") { "\($0)\($1.key): \($1.value)\n" })

        --------------BODY---------------
        \(deserializedBody() ?? "UNAVAILABLE")

        ++++++++++++++++++++++++++++++++
        """
    }
}

private extension HTTPRequest {
    func deserializedBody() -> String? {
        if let debuggableBody = body as? CustomDebugStringConvertible {
            return debuggableBody.debugDescription
        }
        guard let body = try? body.encode() else { return nil }
        return try? body.jsonString()
    }
}

public extension HTTPRequest {
    mutating func setDefaultHeaders(with token: String) {
        headers.merge(
            [
                "Authorization": "Bearer \(token)",
            ],
            uniquingKeysWith: { _, second in second }
        )
    }

    var accessToken: String? {
        guard var token = headers["Authorization"] else { return nil }
        if let range = token.range(of: "Bearer ") ?? token.range(of: "Basic ") {
            token.removeSubrange(range)
            return token
        } else {
            return token
        }
    }
}

public enum HTTPAuthMethod: HTTPRequestOption {
    case userAuth
    case noAuth

    public static let defaultOptionValue: HTTPAuthMethod = .userAuth
}

public enum CacheMethod: HTTPRequestOption {
    case neverCache
    case cacheWithLimit(TimeInterval)
    case cacheUntilDate(Date)
    case cacheWithoutExpiry

    public static let defaultOptionValue: CacheMethod = .neverCache
}

public extension HTTPRequest {

    var authMethod: HTTPAuthMethod {
        get { self[option: HTTPAuthMethod.self] }
        set {
            if newValue == .noAuth, let date = nextExpiryDate {
                cacheMethod = .cacheUntilDate(date)
            } else {
                cacheMethod = .neverCache
            }
            self[option: HTTPAuthMethod.self] = newValue
        }
    }

    private var nextExpiryDate: Date? {
//        Calendar.current.nextDate(after: Date(), matching: .init(hour: 23), matchingPolicy: .nextTime)
        nil
    }

    var cacheMethod: CacheMethod {
        get { self[option: CacheMethod.self] }
        set { self[option: CacheMethod.self] = newValue }
    }
}

extension ServerEnvironment: HTTPRequestOption {
    public static let defaultOptionValue: ServerEnvironment? = nil
}

public extension HTTPRequest {

    var serverEnvironment: ServerEnvironment? {
        get { self[option: ServerEnvironment.self] }
        set { self[option: ServerEnvironment.self] = newValue }
    }
}

#if DEBUG

    public enum DebugMockLoadMethod: HTTPRequestOption {
        case simulatorFilePath(String)
        case mockJSON(String)
        case mockValue(Decodable & Sendable)
        case noMock

        public static let defaultOptionValue: DebugMockLoadMethod = .noMock
    }

    public extension HTTPRequest {

        var debugMockLoadMethod: DebugMockLoadMethod {
            get { self[option: DebugMockLoadMethod.self] }
            set { self[option: DebugMockLoadMethod.self] = newValue }
        }
    }

#endif

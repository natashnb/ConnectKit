//
//  HTTPResponse.swift
//  NetworkLoader
//
//  Created by Natash Bangera on 19/07/24.
//

import Foundation

public struct HTTPResponse: Sendable {
    public let request: HTTPRequest
    let response: HTTPURLResponse
    public let body: Data

    public var status: HTTPStatus {
        // A struct of similar construction to HTTPMethod
        HTTPStatus(rawValue: response.statusCode)
    }

    public var message: String {
        HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
    }

    public var headers: [AnyHashable: Any] { response.allHeaderFields }

    public init(request: HTTPRequest, response: HTTPURLResponse, body: Data) {
        self.request = request
        self.response = response
        self.body = body
    }
}

public struct HTTPStatus: Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}

extension HTTPResponse: CustomDebugStringConvertible {

    public var debugDescription: String {
        """
        ++++++++++++++++++++++++++++++++
        <\(request.identifier)> [RESPONSE] \(response.statusCode) (\(message.uppercased())) \(
            request.method.rawValue
                .uppercased()
        ) \(response.url?.absoluteString ?? "")

         -------------HEADERS-------------
        \(response.headers.reduce("") { "\($0)\($1.key): \($1.value)\n" })

        --------------BODY---------------
        \(deserializedBody() ?? String(data: body, encoding: .utf8) ?? "UNAVAILABLE")

        ++++++++++++++++++++++++++++++++
        """
    }
}

private extension HTTPResponse {
    func deserializedBody() -> String? {
        try? body.jsonString()
    }
}

private extension HTTPURLResponse {
    var headers: [String: String] {
        (allHeaderFields as? [String: String]) ?? [:]
    }
}

public extension HTTPResponse {
    var isStatusCodeValid: Bool {
        Self.isStatusCodeValid(response.statusCode)
    }

    static func isStatusCodeValid(_ statusCode: Int) -> Bool {
        200 ..< 300 ~= statusCode
    }
}

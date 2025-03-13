//
//  Request.swift
//  NetworkLoader
//
//  Created by Natash Bangera on 19/07/24.
//

import Combine
import Foundation

public struct Request<Response> {
    public let underlyingRequest: HTTPRequest
    public let decode: (HTTPResponse) throws -> Response

    public init(underlyingRequest: HTTPRequest, decode: @escaping (HTTPResponse) throws -> Response) {
        self.underlyingRequest = underlyingRequest
        self.decode = decode
    }
}

public extension Request where Response: Decodable {

    // request a value that's decoded using a JSON decoder
//    init(underlyingRequest: HTTPRequest) {
//        self.init(underlyingRequest: underlyingRequest, decoder: JSONDecoder())
//    }

    // request a value that's decoded using the specified decoder
    // requires: import Combine
//    init<D: TopLevelDecoder>(underlyingRequest: HTTPRequest, decoder: D) where D.Input == Data {
//        self.init(
//            underlyingRequest: underlyingRequest,
//            decode: { try decoder.decode(Response.self, from: $0.body) }
//        )
//    }

    init(underlyingRequest: HTTPRequest, decoder: JSONDecoder = .init()) {
        self.init(underlyingRequest: underlyingRequest, decode: CommonDecoder(decoder: decoder).decode(response:))
    }
}

// Usage example
// extension Request where Response == Person {
//    static func person(_ id: Int) -> Request<Response> {
//        return Request(personID: id)
//    }
//
//    init(personID: Int) {
//        let request = HTTPRequest(path: "/api/person/\(personID)/")
//
//        // because Person: Decodable, this will use the initializer that automatically provides a JSONDecoder to
//        interpret the response
//        self.init(underlyingRequest: request)
//    }
// }

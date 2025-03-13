//
//  HTTPResult.swift
//  NetworkLoader
//
//  Created by Natash Bangera on 19/07/24.
//

import Foundation

public typealias HTTPResult = Result<HTTPResponse, HTTPError>

public extension HTTPResult {

    var request: HTTPRequest {
        switch self {
        case let .success(response): response.request
        case let .failure(error): error.request
        }
    }

    var response: HTTPResponse? {
        switch self {
        case let .success(response): response
        case let .failure(error): error.response
        }
    }

    var error: HTTPError? {
        switch self {
        case .success: nil
        case let .failure(error): error
        }
    }

    init(request: HTTPRequest, responseData: Data?, response: URLResponse?, error: Error?) {
        var httpResponse: HTTPResponse?
        if let hResponse = response as? HTTPURLResponse {
            httpResponse = HTTPResponse(request: request, response: hResponse, body: responseData ?? Data())
        }

        if let urlError = error as? URLError {
            let code: HTTPError.Code
            switch urlError.code {
            case .badURL: code = .invalidRequest
            case .unsupportedURL: code = .invalidRequest
            case .cannotFindHost: code = .cannotConnect
            case .notConnectedToInternet: code = .cannotConnect
            case .timedOut: code = .cannotConnect
            case .networkConnectionLost: code = .cannotConnect
            case .cannotConnectToHost: code = .cannotConnect
            case .dnsLookupFailed: code = .cannotConnect
            case .resourceUnavailable: code = .cannotConnect
            case .cancelled: code = .cancelled
            case .httpTooManyRedirects: code = .cannotConnect
            case .redirectToNonExistentLocation: code = .cannotConnect
            case .badServerResponse: code = .invalidResponse
            default: code = .unknown
            }
            self = .failure(HTTPError(code: code, request: request, response: httpResponse, underlyingError: urlError))
        } else if let someError = error {
            // an error, but not a URL error
            self =
                .failure(HTTPError(
                    code: .unknown,
                    request: request,
                    response: httpResponse,
                    underlyingError: someError
                ))
        } else if let hResponse = httpResponse {
            // not an error, and an HTTPURLResponse
            guard Self.isAppOutdated(from: hResponse.headers) == false else {
                self =
                    .failure(.init(
                        code: .outdatedAppVersion,
                        request: request,
                        response: hResponse,
                        underlyingError: error
                    ))
                return
            }

            self = .success(hResponse)
        } else {
            // not an error, but also not an HTTPURLResponse
            self = .failure(HTTPError(code: .invalidResponse, request: request, response: nil, underlyingError: error))
        }
    }
}

extension HTTPResult {

    private static func isAppOutdated(from _: [AnyHashable: Any]) -> Bool {
        // TODO: Extract logic to a provider.
        false
    }
}

extension HTTPResult: @retroactive CustomStringConvertible {

    public var description: String {
        debugDescription
    }
}

extension HTTPResult: @retroactive CustomDebugStringConvertible {

    public var debugDescription: String {
        response?.debugDescription ?? "UNAVAILABLE"
    }
}

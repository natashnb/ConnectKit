//
//  HTTPError.swift
//  NetworkLoader
//
//  Created by Natash Bangera on 19/07/24.
//

import Foundation

/// Describes an error encounted during request loading.
public struct HTTPError: Error {

    /// The high-level classification of this error
    public let code: Code

    /// The HTTPRequest that resulted in this error
    public let request: HTTPRequest

    /// Any HTTPResponse (partial or otherwise) that we might have
    public let response: HTTPResponse?

    /// If we have more information about the error that caused this, stash it here
    public let underlyingError: Error?

    public enum Code: Int, Sendable {
        case invalidRequest // the HTTPRequest could not be turned into a URLRequest
        case cannotConnect // some sort of connectivity problem
        case cancelled // the user cancelled the request
        case insecureConnection // couldn't establish a secure connection to the server
        case invalidResponse // the system did not receive a valid HTTP response
        case tokenRefreshFailure
        case outdatedAppVersion
        case resetInProgress
        case unknown // we have no idea what the problem is
    }

    public init(
        code: HTTPError.Code,
        request: HTTPRequest,
        response: HTTPResponse? = nil,
        underlyingError: Error? = nil
    ) {
        self.code = code
        self.request = request
        self.response = response
        self.underlyingError = underlyingError
    }

    public var errorCode: Int {
        code.rawValue
    }
}

public func ~= (code: HTTPError.Code, error: any Error) -> Bool {
    guard let error = error as? HTTPError else { return false }
    return error.code == code
}

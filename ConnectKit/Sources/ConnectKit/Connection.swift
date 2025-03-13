//
//  Connection.swift
//  NetworkLoader
//
//  Created by Natash Bangera on 19/07/24.
//

import Foundation

public class Connection {

    private let loader: HTTPLoader
    private let validateResponse: (HTTPResponse) throws -> Void

    public init(
        loader: HTTPLoader,
        validateResponse: @escaping (HTTPResponse) throws -> Void
    ) {
        self.loader = loader
        self.validateResponse = validateResponse
    }

    public func request<ResponseType>(_ request: Request<ResponseType>) async throws -> ResponseType {
        let result = await loader.load(request: request.underlyingRequest)
        switch result {
        case let .success(response):
            try validate(response: response)
            return try request.decode(response)
        case let .failure(error):
            throw error
        }
    }

    public func validate(response: HTTPResponse) throws {
        try validateResponse(response)
    }
}

//
//  ApplyEnvironmentLoader.swift
//  NetworkLoader
//
//  Created by Natash Bangera on 19/07/24.
//

import Foundation

/// Use this loader to modify the ``HTTPRequest`` with the correct host and headers
public class ApplyEnvironmentLoader: HTTPLoader {

    private let environment: ServerEnvironment

    public init(environment: ServerEnvironment) {
        self.environment = environment
        super.init()
    }

    override public func load(request: HTTPRequest) async -> HTTPResult {
        var copy = request

        let requestEnvironment = request.serverEnvironment ?? environment

        if copy.host.isNilOrEmpty == true {
            copy.host = requestEnvironment.host
        }

        if let port = requestEnvironment.port, copy.url?.port == nil {
            copy.port = port
        }

        if copy.path.hasPrefix(environment.pathPrefix) == false {
            copy.path = requestEnvironment.pathPrefix + request.path
        }

        for (header, value) in await requestEnvironment.headers() {
            if copy.headers[header] == nil {
                copy.headers[header] = value
            }
        }

        return await super.load(request: copy)
    }
}

fileprivate extension Optional where Wrapped: Collection {
    var isNilOrEmpty: Bool {
        self?.isEmpty ?? true
    }
}

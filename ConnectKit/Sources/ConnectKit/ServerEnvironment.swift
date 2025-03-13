//
//  ServerEnvironment.swift
//  NetworkLoader
//
//  Created by Natash Bangera on 19/07/24.
//

import Foundation

/// Use to define a backend/server environment.
public struct ServerEnvironment: Sendable {
    public var host: String
    public var pathPrefix: String
    public var headers: @Sendable () async -> [String: String]
//    public var query: [URLQueryItem]
    public var port: Int?

    public init(
        host: String,
        pathPrefix: String = "/",
        headers: @escaping @Sendable () async -> [String: String] = { [:] },
//        query: [URLQueryItem] = []
        port: Int? = nil
    ) {
        // make sure the pathPrefix starts with a /
        let prefix = pathPrefix.hasPrefix("/") ? "" : "/"

        self.host = host
        self.pathPrefix = prefix + pathPrefix
        self.headers = headers
//        self.query = query
        self.port = port
    }
}

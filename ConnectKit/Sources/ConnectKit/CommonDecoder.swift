//
//  CommonDecoder.swift
//  NetworkLoader
//
//  Created by Natash Bangera on 19/07/24.
//

import Foundation

public struct CommonDecoder<Response: Decodable> {

    let decoder: JSONDecoder

    public init(decoder: JSONDecoder) {
        self.decoder = decoder
    }

    public func decode(response: HTTPResponse) throws -> Response {
        try decoder.decode(Response.self, from: response.body)
    }
}

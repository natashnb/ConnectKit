//
//  HTTPBody.swift
//  NetworkLoader
//
//  Created by Natash Bangera on 19/07/24.
//

import Foundation
import UniformTypeIdentifiers

/// Protocol to define a HTTP request body.
public protocol HTTPBody: Sendable {
    var isEmpty: Bool { get }
    var additionalHeaders: [String: String] { get }
    func encode() throws -> Data
}

public extension HTTPBody {
    var isEmpty: Bool { false }
    var additionalHeaders: [String: String] { [:] }
}

/// A request body with no data.
public struct EmptyBody: HTTPBody {
    public let isEmpty = true

    public init() {}
    public func encode() throws -> Data { Data() }
}

extension EmptyBody: CustomDebugStringConvertible {
    public var debugDescription: String { "--" }
}

/// A raw data request body.
public struct DataBody: HTTPBody {
    private let data: Data

    public var isEmpty: Bool { data.isEmpty }
    public var additionalHeaders: [String: String]

    public init(_ data: Data, additionalHeaders: [String: String] = [:]) {
        self.data = data
        self.additionalHeaders = additionalHeaders
    }

    public func encode() throws -> Data { data }
}

extension DataBody: CustomDebugStringConvertible {
    public var debugDescription: String {
        NSString(data: data, encoding: String.Encoding.utf8.rawValue) as String? ?? ""
    }
}

/// HTTPBody that can be encoded to JSON using a JSONEncoder
public struct JSONEncodableBody: HTTPBody {
    public let isEmpty: Bool = false
    public var additionalHeaders = [
        "Content-Type": "application/json; charset=utf-8",
    ]

    private let encoder: @Sendable () throws -> Data

    public init(_ value: some Encodable & Sendable, encoder: JSONEncoder = JSONEncoder()) {
        self.encoder = { try encoder.encode(value) }
    }

    public func encode() throws -> Data { try encoder() }
}

extension JSONEncodableBody: CustomDebugStringConvertible {
    public var debugDescription: String {
        guard !isEmpty else { return "--" }
        guard let data = try? encode() else { return "UNAVAILABLE" }
        return (try? data.jsonString()) ?? "UNAVAILABLE"
    }
}

/// HTTPBody for a JSON dictionary. Values in the `[String: Any]` ``values`` dictionary will be encoded using
/// ``JSONSerialization``.
/// This uses a nonisolated(unsafe) [String:Any] property – it is incumbent on the consumer
/// to ensure no concurrency issues while using this type of `HTTPBody`
public struct JSONBody: HTTPBody {
    public var isEmpty: Bool { values.isEmpty }
    public var additionalHeaders = [
        "Content-Type": "application/json; charset=utf-8",
    ]

    nonisolated(unsafe)
    public let values: [String: Any]

    public init(_ values: [String: Any]) {
        self.values = values
    }

    public func encode() throws -> Data {
        try JSONSerialization.data(withJSONObject: values)
    }
}

extension JSONBody: CustomDebugStringConvertible {
    public var debugDescription: String {
        values.reduce("") { "\($0)\n\($1.key): \($1.value)" }
    }
}

/// HTTPBody for a top-level JSON array of objects. Values will be encoded using ``JSONSerialization``.
public struct ArrayJSONBody: HTTPBody {
    public var isEmpty: Bool { values.isEmpty }
    public var additionalHeaders = [
        "Content-Type": "application/json; charset=utf-8",
    ]

    public let values: [[String: any Sendable]]

    public init(_ values: [[String: any Sendable]]) {
        self.values = values
    }

    public func encode() throws -> Data {
        try JSONSerialization.data(withJSONObject: values)
    }
}

/// HTTPBody for a form url encoded request.
public struct FormBody: HTTPBody {
    public var isEmpty: Bool { values.isEmpty }
    public let additionalHeaders = [
        "Content-Type": "application/x-www-form-urlencoded; charset=utf-8",
    ]

    private let values: [URLQueryItem]

    public init(_ values: [URLQueryItem]) {
        self.values = values
    }

    public init(_ values: [String: String]) {
        let queryItems = values.map { URLQueryItem(name: $0.key, value: $0.value) }
        self.init(queryItems)
    }

    public func encode() throws -> Data {
        let pieces = values.map(urlEncode)
        let bodyString = pieces.joined(separator: "&")
        return Data(bodyString.utf8)
    }

    private func urlEncode(_ queryItem: URLQueryItem) -> String {
        let name = urlEncode(queryItem.name)
        let value = urlEncode(queryItem.value ?? "")
        return "\(name)=\(value)"
    }

    private func urlEncode(_ string: String) -> String {
        let allowedCharacters = CharacterSet.alphanumerics
        return string.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? ""
    }
}

extension FormBody: CustomDebugStringConvertible {
    public var debugDescription: String {
        values.reduce("") { "\($0)\n\($1.name): \($1.value ?? "")" }
    }
}

extension Data {

    /// Used to convert json data to a pretty printed string for debugging.
    /// - Returns: Pretty printed json.
    func jsonString() throws -> String? {
        let object = try JSONSerialization.jsonObject(with: self, options: [])
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted])
        return String(data: data, encoding: .utf8)
    }
}

/// Use for MultipartForm data upload
/// NOTE: Not optimized for large files
/// Not recommended for usage in production
public struct MultipartFormBody: HTTPBody {

    public var isEmpty: Bool { values.isEmpty }

    public let additionalHeaders: [String: String]

    /// Used to separate form elements in the encoded data.
    private let boundary: String

    public let values: [Content]

    public init(
        values: [Content],
        boundary: String = "Boundary-\(UUID().uuidString)"
    ) {
        additionalHeaders = [
            "Content-Type": "multipart/form-data; boundary=\(boundary)",
        ]
        self.values = values
        self.boundary = boundary
    }

    public func encode() throws -> Data {

        var data = Data()

        for value in values {
            data.appendBoundary(boundary)
            data.append(value)
        }

        data.append(Data("--\(boundary)--".utf8))

        return data
    }

    public func writeToFile(with filename: String? = nil) async throws -> URL {

        var tempFile = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        tempFile.appendPathComponent(filename ?? UUID().uuidString)

        try Data("\r\n".utf8).write(to: tempFile)

        let handle = try FileHandle(forWritingTo: tempFile)

        let boundaryData = Data("--\(boundary)\r\n".utf8)

        for value in values {

            try handle.write(contentsOf: boundaryData)

            switch value {
            case let .data(key: key, data: data):
                try handle.write(contentsOf: Data("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".utf8))
                try handle.write(contentsOf: data)
            case let .jsonData(key: key, data: data):
                try handle.write(contentsOf: Data("Content-Disposition: form-data; name=\"\(key)\"\r\n".utf8))
                try handle.write(contentsOf: Data("Content-Type: application/json; charset=utf-8\r\n\r\n".utf8))
                try handle.write(contentsOf: data)
            case let .text(key: key, string: string):
                try handle.write(contentsOf: Data("Content-Disposition: form-data; name=\"\(key)\"\r\n".utf8))
                try handle.write(contentsOf: Data("Content-Type: text/plain; charset=utf-8\r\n\r\n".utf8))
                try handle.write(contentsOf: Data(string.utf8))
            case let .png(key: key, filename: filename, data: data):
                try handle
                    .write(contentsOf: Data(
                        "Content-Disposition: form-data; name=\"\(key)\"; filename=\"\(filename ?? key)\"\r\n"
                            .utf8
                    ))
                try handle.write(contentsOf: Data("Content-Type: image/png\r\n\r\n".utf8))
                try handle.write(contentsOf: data)
            case let .jpeg(key: key, filename: filename, data: data):
                try handle
                    .write(contentsOf: Data(
                        "Content-Disposition: form-data; name=\"\(key)\"; filename=\"\(filename ?? key)\"\r\n"
                            .utf8
                    ))
                try handle.write(contentsOf: Data("Content-Type: image/jpeg\r\n\r\n".utf8))
                try handle.write(contentsOf: data)
            case let .mp4(key: key, filename: filename, data: data):
                try handle
                    .write(contentsOf: Data(
                        "Content-Disposition: form-data; name=\"\(key)\"; filename=\"\(filename ?? key)\"\r\n"
                            .utf8
                    ))
                try handle.write(contentsOf: Data("Content-Type: video/mp4\r\n\r\n".utf8))
                try handle.write(contentsOf: data)
            case let .video(key: key, filename: filename, utType: utType, data: data):
                try handle
                    .write(contentsOf: Data(
                        "Content-Disposition: form-data; name=\"\(key)\"; filename=\"\(filename ?? key)\"\r\n"
                            .utf8
                    ))
                try handle
                    .write(
                        contentsOf: Data(
                            "Content-Type: \(utType.preferredMIMEType ?? utType.identifier)\r\n\r\n"
                                .utf8
                        )
                    )
                try handle.write(contentsOf: data)
            case let .pdf(key: key, filename: filename, data: data):
                let fileName = "\(key).pdf"
                try handle
                    .write(
                        contentsOf: Data(
                            "Content-Disposition: form-data; name=\"\(key)\"; filename=\"\(filename ?? fileName)\"\r\n"
                                .utf8
                        )
                    )
                try handle.write(contentsOf: Data("Content-Type: application/pdf\r\n\r\n".utf8))
                try handle.write(contentsOf: data)
            case let .pngURL(key: key, filename: filename, url: url):
                try handle
                    .write(contentsOf: Data(
                        "Content-Disposition: form-data; name=\"\(key)\"; filename=\"\(filename ?? key)\"\r\n"
                            .utf8
                    ))
                try handle.write(contentsOf: Data("Content-Type: image/png\r\n\r\n".utf8))
                try await append(from: url, to: handle)
            case let .jpegURL(key: key, filename: filename, url: url):
                try handle
                    .write(contentsOf: Data(
                        "Content-Disposition: form-data; name=\"\(key)\"; filename=\"\(filename ?? key)\"\r\n"
                            .utf8
                    ))
                try handle.write(contentsOf: Data("Content-Type: image/jpeg\r\n\r\n".utf8))
                try await append(from: url, to: handle)
            case let .imageURL(key: key, filename: filename, utType: utType, url: url):
                try handle
                    .write(contentsOf: Data(
                        "Content-Disposition: form-data; name=\"\(key)\"; filename=\"\(filename ?? key)\"\r\n"
                            .utf8
                    ))
                try handle
                    .write(contentsOf: Data(
                        "Content-Type: \(utType.preferredMIMEType ?? utType.identifier)\r\n\r\n"
                            .utf8
                    ))
                try await append(from: url, to: handle)
            case let .pdfURL(key: key, filename: filename, url: url):
                let fileName = "\(key).pdf"
                try handle
                    .write(
                        contentsOf: Data(
                            "Content-Disposition: form-data; name=\"\(key)\"; filename=\"\(filename ?? fileName)\"\r\n"
                                .utf8
                        )
                    )
                try handle.write(contentsOf: Data("Content-Type: application/pdf\r\n\r\n".utf8))
                try await append(from: url, to: handle)
            case let .mp4URL(key: key, filename: filename, url: url):
                try handle
                    .write(contentsOf: Data(
                        "Content-Disposition: form-data; name=\"\(key)\"; filename=\"\(filename ?? key)\"\r\n"
                            .utf8
                    ))
                try handle.write(contentsOf: Data("Content-Type: video/mp4\r\n\r\n".utf8))
                try await append(from: url, to: handle)
            case
                let .file(key: key, filename: filename, utType: utType, url: url),
                let .videoURL(key: key, filename: filename, utType: utType, url: url):
                try handle
                    .write(contentsOf: Data(
                        "Content-Disposition: form-data; name=\"\(key)\"; filename=\"\(filename ?? url.lastPathComponent)\"\r\n"
                            .utf8
                    ))
                try handle
                    .write(
                        contentsOf: Data(
                            "Content-Type: \(utType.preferredMIMEType ?? utType.identifier)\r\n\r\n"
                                .utf8
                        )
                    )
                try await append(from: url, to: handle)
            }

            try handle.write(contentsOf: Data("\r\n".utf8))
        }

        try handle.write(contentsOf: Data("--\(boundary)--".utf8))

        try handle.synchronize()
        try handle.close()

        return tempFile
    }

    private func append(from: URL, to: FileHandle) async throws {

        var buffer = [UInt8]()
        var count = 0
        for try await bytes in from.resourceBytes {
            buffer.append(bytes)
            count += 1

            if count == 1024 * 1024 {
                let tempBuffer = buffer
                buffer = []
                count = 0
                let data = Data(tempBuffer)
                try to.write(contentsOf: data)
            }
        }

        if !buffer.isEmpty {
            let data = Data(buffer)
            try to.write(contentsOf: data)
        }
    }
}

public extension MultipartFormBody {

    /// Locally supported content types for form upload.
    enum Content: Sendable {
        case data(key: String, data: Data)
        case jsonData(key: String, data: Data)
        case text(key: String, string: String)
        case png(key: String, filename: String?, data: Data)
        case jpeg(key: String, filename: String?, data: Data)
        case pdf(key: String, filename: String?, data: Data)
        case mp4(key: String, filename: String?, data: Data)
        case video(key: String, filename: String?, utType: UTType, data: Data)
        case pngURL(key: String, filename: String?, url: URL)
        case jpegURL(key: String, filename: String?, url: URL)
        case imageURL(key: String, filename: String?, utType: UTType, url: URL)
        case pdfURL(key: String, filename: String?, url: URL)
        case mp4URL(key: String, filename: String?, url: URL)
        case videoURL(key: String, filename: String?, utType: UTType, url: URL)
        case file(key: String, filename: String?, utType: UTType, url: URL)
    }
}

extension MultipartFormBody: CustomDebugStringConvertible {
    public var debugDescription: String {
        values.reduce("", appendToDescription(_:content:))
    }

    private func appendToDescription(_ description: String, content: Content) -> String {

        let contentDescription = switch content {
        case
            let .data(key: key, data: data),
            let .jsonData(key: key, data: data):
            "\(key): \(data.count) bytes"
        case
            let .png(key: key, filename: filename, data: data),
            let .jpeg(key: key, filename: filename, data: data),
            let .mp4(key: key, filename: filename, data: data),
            let .pdf(key: key, filename: filename, data: data):
            "\(key): filename \(filename ?? key) \(data.count) bytes"
        case let .text(key: key, string: string):
            "\(key): \(string)"
        case let .video(key: key, filename: filename, utType: utType, data: data):
            "\(key): filename \(filename ?? key) \(data.count) bytes, type: \(utType), identifier: \(utType.identifier)"
        case
            let .file(key: key, filename: filename, utType: utType, url: url),
            let .videoURL(key: key, filename: filename, utType: utType, url: url):
            "\(key) type: \(utType), filename: \(filename ?? key), identifier: \(utType.identifier), url: \(url.relativePath)"
        case
            let .pngURL(key: key, filename: filename, url: url),
            let .jpegURL(key: key, filename: filename, url: url),
            let .imageURL(key: key, filename: filename, utType: _, url: url),
            let .pdfURL(key: key, filename: filename, url: url),
            let .mp4URL(key: key, filename: filename, url: url):
            "\(key): filename \(filename ?? key) \(url.relativePath)"
        }

        return description + "\n" + contentDescription
    }
}

private extension Data {

    mutating func appendBoundary(_ boundary: String) {
        if !isEmpty {
            append(Data("\r\n".utf8))
        }
        append(Data("--\(boundary)\r\n".utf8))
    }

    mutating func append(_ content: MultipartFormBody.Content) {

        switch content {
        case let .data(key: key, data: data):
            append(Data("Content-Disposition: form-data; name=\"\(key)\"\r\n".utf8))
            append(data)
        case let .jsonData(key: key, data: data):
            append(Data("Content-Disposition: form-data; name=\"\(key)\"\r\n".utf8))
            append(Data("Content-Type: application/json; charset=utf-8\r\n\r\n".utf8))
            append(data)
        case let .text(key: key, string: string):
            append(Data("Content-Disposition: form-data; name=\"\(key)\"\r\n".utf8))
            append(Data("Content-Type: text/plain; charset=utf-8\r\n\r\n".utf8))
            append(Data(string.utf8))
        case let .png(key: key, filename: filename, data: data):
            append(Data("Content-Disposition: form-data; name=\"\(key)\"; filename=\"\(filename ?? key)\"\r\n".utf8))
            append(Data("Content-Type: image/png\r\n\r\n".utf8))
            append(data)
        case let .jpeg(key: key, filename: filename, data: data):
            append(Data("Content-Disposition: form-data; name=\"\(key)\"; filename=\"\(filename ?? key)\"\r\n".utf8))
            append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
            append(data)
        case let .mp4(key: key, filename: filename, data: data):
            append(Data("Content-Disposition: form-data; name=\"\(key)\"; filename=\"\(filename ?? key)\"\r\n".utf8))
            append(Data("Content-Type: video/mp4\r\n\r\n".utf8))
            append(data)
        case let .video(key: key, filename: filename, utType: utType, data: data):
            append(Data("Content-Disposition: form-data; name=\"\(key)\"; filename=\"\(filename ?? key)\"\r\n".utf8))
            append(Data("Content-Type: \(utType.preferredMIMEType ?? utType.identifier)\r\n\r\n".utf8))
            append(data)
        case let .pdf(key: key, filename: filename, data: data):
            let fileName = "\(key).pdf"
            append(Data(
                "Content-Disposition: form-data; name=\"\(key)\"; filename=\"\(filename ?? fileName)\"\r\n"
                    .utf8
            ))
            append(Data("Content-Type: application/pdf\r\n\r\n".utf8))
            append(data)
        case let .pngURL(key: key, filename: filename, url: url):
            let data = (try? Data(contentsOf: url)) ?? .init()
            append(Data("Content-Disposition: form-data; name=\"\(key)\"; filename=\"\(filename ?? key)\"\r\n".utf8))
            append(Data("Content-Type: image/png\r\n\r\n".utf8))
            append(data)
        case let .jpegURL(key: key, filename: filename, url: url):
            let data = (try? Data(contentsOf: url)) ?? .init()
            append(Data("Content-Disposition: form-data; name=\"\(key)\"; filename=\"\(filename ?? key)\"\r\n".utf8))
            append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
            append(data)
        case let .imageURL(key: key, filename: filename, utType: utType, url: url):
            let data = (try? Data(contentsOf: url)) ?? .init()
            append(Data("Content-Disposition: form-data; name=\"\(key)\"; filename=\"\(filename ?? key)\"\r\n".utf8))
            append(Data("Content-Type: \(utType.preferredMIMEType ?? utType.identifier)\r\n\r\n".utf8))
            append(data)
        case let .pdfURL(key: key, filename: filename, url: url):
            let data = (try? Data(contentsOf: url)) ?? .init()
            let fileName = "\(key).pdf"
            append(Data(
                "Content-Disposition: form-data; name=\"\(key)\"; filename=\"\(filename ?? fileName)\"\r\n"
                    .utf8
            ))
            append(Data("Content-Type: application/pdf\r\n\r\n".utf8))
            append(data)
        case let .mp4URL(key: key, filename: filename, url: url):
            let data = (try? Data(contentsOf: url)) ?? .init()
            append(Data("Content-Disposition: form-data; name=\"\(key)\"; filename=\"\(filename ?? key)\"\r\n".utf8))
            append(Data("Content-Type: video/mp4\r\n\r\n".utf8))
            append(data)
        case
            let .file(key: key, filename: filename, utType: utType, url: url),
            let .videoURL(key: key, filename: filename, utType: utType, url: url):
            let data = (try? Data(contentsOf: url)) ?? .init()
            append(Data(
                "Content-Disposition: form-data; name=\"\(key)\"; filename=\"\(filename ?? url.lastPathComponent)\"\r\n"
                    .utf8
            ))
            append(Data("Content-Type: \(utType.preferredMIMEType ?? utType.identifier)\r\n\r\n".utf8))
            append(data)
        }

        append(Data("\r\n".utf8))
    }
}

private extension String {

    var formEncoded: String {
        let allowedCharacters = CharacterSet.alphanumerics
        return addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? ""
    }
}

//
//  CacheLoader.swift
//  NetworkLoader
//
//  Created by Natash Bangera on 19/07/24.
//

import Foundation

public final class CacheLoader: HTTPLoader {

    let cache: URLCache
    let dateProvider: () -> Date

    public init(
        cache: URLCache = .shared,
        dateProvider: @escaping () -> Date
    ) {
        self.cache = cache
        self.dateProvider = dateProvider
        super.init()
    }

    override public func load(request: HTTPRequest) async -> HTTPResult {

        if Task.isCancelled {
            return HTTPResult.failure(.init(code: .cancelled, request: request))
        }

        if case .neverCache = request.cacheMethod {
            return await super.load(request: request)
        }

        guard let urlRequest = try? request.getURLRequest() else {
            return await super.load(request: request)
        }

        if
            let response = cache.cachedResponse(for: urlRequest),
            let expiryDate = response.userInfo?[Self.expiryDateKey] as? Date,
            dateProvider() < expiryDate
        {
            return .init(request: request, responseData: response.data, response: response.response, error: nil)
        } else {
            cache.removeCachedResponse(for: urlRequest)

            let result = await super.load(request: request)

            if let responseToCache = getCachedURLResponse(from: result) {
                cache.storeCachedResponse(responseToCache, for: urlRequest)
            }

            return result
        }
    }
}

extension CacheLoader {

    private static let expiryDateKey = "httpResponseCacheExpiryDate"

    private func getCachedURLResponse(from result: HTTPResult) -> CachedURLResponse? {
        guard
            let response = result.response,
            response.isStatusCodeValid
        else { return nil }

        switch response.request.cacheMethod {
        case .neverCache: return nil
        case .cacheWithoutExpiry:
            guard let date = Calendar.current.date(byAdding: .day, value: 1, to: dateProvider()) else { return nil }
            return CachedURLResponse(
                response: response.response,
                data: response.body,
                userInfo: [Self.expiryDateKey: date],
                storagePolicy: .allowed
            )
        case let .cacheUntilDate(expiryDate):
            return CachedURLResponse(
                response: response.response,
                data: response.body,
                userInfo: [Self.expiryDateKey: expiryDate],
                storagePolicy: .allowed
            )
        case let .cacheWithLimit(timeLimit):
            let date = dateProvider().addingTimeInterval(timeLimit)
            return CachedURLResponse(
                response: response.response,
                data: response.body,
                userInfo: [Self.expiryDateKey: date],
                storagePolicy: .allowed
            )
        }
    }
}

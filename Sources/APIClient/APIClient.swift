//
//  API.swift
//
//
//  Created by ErrorErrorError on 9/4/22.
//

import Combine
import ComposableArchitecture
import Foundation
import Logger

// MARK: - APIClient

public protocol APIClient {
    @discardableResult
    func request<O: Decodable>(
        _ request: Request<O>
    ) async throws -> O
}

// MARK: - Endpoint

protocol Endpoint {
    associatedtype Output: Decodable

    var base: URL { get }
    var path: [CustomStringConvertible] { get }
    var query: [Query] { get }
    var method: Request<Output>.Method { get }
    var headers: [String: CustomStringConvertible]? { get }
}

extension Endpoint {
    func build() -> Request<Output> {
        .init(
            base: base,
            path: path,
            query: query,
            method: method,
            headers: headers
        )
    }
}

// MARK: - APIClientKey

public enum APIClientKey: DependencyKey {
    public static var liveValue: any APIClient = APIClientLive()
}

public extension DependencyValues {
    var apiClient: any APIClient {
        get { self[APIClientKey.self] }
        set { self[APIClientKey.self] = newValue }
    }
}

// MARK: - Request

public struct Request<O: Decodable> {
    var base: URL
    var path: [CustomStringConvertible] = []
    var query: [Query]?
    var method: Method = .get
    var headers: [String: CustomStringConvertible]?
    var decoder: JSONDecoder = .init()

    enum Method: CustomStringConvertible {
        case get
        case post(Data)
        case put(Data)

        var stringValue: String {
            switch self {
            case .get:
                return "GET"
            case .post:
                return "POST"
            case .put:
                return "PUT"
            }
        }

        var description: String {
            switch self {
            case .get:
                return "GET"
            case let .post(data):
                return "POST: \(String(data: data, encoding: .utf8) ?? "Unknown")"
            case let .put(data):
                return "PUT: \(String(data: data, encoding: .utf8) ?? "Unknown")"
            }
        }
    }
}

// MARK: - EmptyResponse

public struct EmptyResponse: Decodable {}

public typealias NoResponseRequest = Request<EmptyResponse>

typealias Query = URLQueryItem

extension Query {
    init(
        name: String,
        _ value: some CustomStringConvertible
    ) {
        self.init(
            name: name,
            value: value.description
        )
    }
}

public extension [Query] {
    init(_ dictionary: [String: CustomStringConvertible]) {
        self = dictionary.map { .init(name: $0.key, $0.value) }
    }
}

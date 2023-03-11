//
//  File.swift
//
//
//  Created by ErrorErrorError on 3/8/23.
//
//

import Foundation

// MARK: - ArmEndpoint

public struct ArmEndpoint<D: Decodable>: Endpoint {
    var base = URL(string: "https://arm.haglund.dev/api/v2").unsafelyUnwrapped
    var path: [CustomStringConvertible] = []
    var query: [Query] = []
    var method: Request<D>.Method
    var headers: [String: CustomStringConvertible]?
}

public extension ArmEndpoint {
    static func ids(
        _ id: CustomStringConvertible,
        _ source: String
    ) -> ArmEndpoint<ArmModels.Identifiers> {
        .init(
            path: ["ids"],
            query: .init([
                "source": source,
                "id": id,
                "include": "anilist,myanimelist,kitsu"
            ]),
            method: .get
        )
    }
}

public extension Request {
    static func arm<D: Decodable>(_ endpoint: ArmEndpoint<D>) -> Request<D> {
        endpoint.build()
    }
}

// MARK: - ArmModels

public enum ArmModels {}

// MARK: ArmModels.Identifiers

public extension ArmModels {
    struct Identifiers: Decodable {
        public let anilist: Int?
        public let myanimelist: Int?
        public let kitsu: Int?
    }
}

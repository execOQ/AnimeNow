//
//  MalAPI.swift
//
//
//  Created by ErrorErrorError on 2/16/23.
//
//

import AuthenticationClient
import ComposableArchitecture
import CryptoKit
import Foundation
import Utilities

// MARK: - MalEndpoint

public struct MalEndpoint<D: Decodable>: Endpoint {
    var base = URL(string: "https://api.myanimelist.net/v2").unsafelyUnwrapped
    var path: [CustomStringConvertible] = []
    var query: [Query] = []
    var method: Request<D>.Method = .get
    var headers: [String: CustomStringConvertible]?
}

public extension MalEndpoint {
    static func getUserAnimeList(
        accessToken: String,
        status: MalModels.Status? = nil,
        sort: MalModels.Sort? = .list_updated_at,
        limit: Int = 100,
        offset: Int = 0
    ) -> MalEndpoint<MalModels.Pagination<MalModels.AnimeList>> {
        .init(
            path: ["users", "@me", "animelist"],
            query: [
                status.flatMap { .init(name: "status", $0.rawValue) },
                sort.flatMap { .init(name: "sort", $0.rawValue) },
                .init(name: "limit", limit),
                .init(name: "offset", offset),
                .init(
                    name: "fields",
                    MalModels.Pagination<MalModels.AnimeList>.fields()
                        .joined(separator: ",")
                )
            ]
            .compactMap { $0 },
            method: .get,
            headers: [
                "Authorization": "Bearer \(accessToken)"
            ]
        )
    }

    static func retrieveToken(
        clientId: String,
        code: String,
        codeVerifier: String
    ) -> MalEndpoint<MalModels.AccessTokenPayload> {
        let body = [
            "client_id": clientId,
            "grant_type": "authorization_code",
            "code": code,
            "code_verifier": codeVerifier
        ]
        .map { "\($0.key)=\($0.value)" }
        .joined(separator: "&")
        .data(using: .utf8) ?? .init()

        return .init(
            base: .init(string: "https://myanimelist.net").unsafelyUnwrapped,
            path: ["v1", "oauth2", "token"],
            method: .post(body),
            headers: [
                "Content-Type": "application/x-www-form-urlencoded"
            ]
        )
    }

    static func refreshToken(
        clientId: String,
        accessToken: String,
        refreshToken: String
    ) -> MalEndpoint<MalModels.AccessTokenPayload> {
        let body = [
            "client_id": clientId,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ]
        .map { "\($0.key)=\($0.value.description)" }
        .joined(separator: "&")
        .data(using: .utf8) ?? .init()

        return .init(
            base: .init(string: "https://myanimelist.net").unsafelyUnwrapped,
            path: ["v1", "oauth2", "token"],
            method: .post(body),
            headers: [
                "Authorization": "Bearer \(accessToken)",
                "Content-Type": "application/x-www-form-urlencoded"
            ]
        )
    }

    static func getUserInfo(token: String) -> MalEndpoint<MalModels.UserInfo> {
        .init(
            path: ["users", "@me"],
            headers: [
                "Authorization": "Bearer \(token)"
            ]
        )
    }

    struct ListItemUpdate {
        let mediaId: Int
        let status: MalModels.Status?
        let numWatchedEpisodes: Int?

        public init(
            mediaId: Int,
            status: MalModels.Status? = nil,
            numWatchedEpisodes: Int? = nil
        ) {
            self.mediaId = mediaId
            self.status = status
            self.numWatchedEpisodes = numWatchedEpisodes
        }
    }

    static func updateListItem(accessToken: String, _ item: ListItemUpdate) -> MalEndpoint<EmptyResponse> {
        let body = [
            "status": item.status?.rawValue,
            "num_watched_episodes": item.numWatchedEpisodes?.description
        ]
        .compactMapValues { $0 }
        .map { "\($0.key)=\($0.value)" }
        .joined(separator: "&")
        .data(using: .utf8) ?? .init()

        return .init(
            path: ["anime", "\(item.mediaId)", "my_list_status"],
            method: .put(body),
            headers: [
                "Authorization": "Bearer \(accessToken)",
                "Content-Type": "application/x-www-form-urlencoded"
            ]
        )
    }
}

public extension Request {
    static func mal<D: Decodable>(_ endpoint: MalEndpoint<D>) -> Request<D> {
        endpoint.build()
    }
}

// MARK: - FieldsParameters

public protocol FieldsParameters {
    static func fields() -> [String]
}

// MARK: - MalModels

public enum MalModels {}

public extension MalModels {
    struct UserInfo: Decodable {
        public let id: Int
        public let name: String
        public let picture: String?
        public let anime_statistics: Statistics?
    }

    struct Statistics: Decodable {
//        public let num_items_watching: Int
//        public let num_items_completed: Int
//        public let num_items_on_hold: Int
//        public let num_items_dropped: Int
//        public let num_items_plan_to_watch: Int
        public let num_items: Int
        public let num_episodes: Int
    }

    struct AccessTokenPayload: Decodable {
        public let token_type: String
        public let access_token: String
        public let refresh_token: String
        public let expires_in: Int
    }

    struct Pagination<D: Decodable & FieldsParameters>: Decodable, FieldsParameters {
        public let data: [D]
        public let paging: Page

        public struct Page: Decodable, FieldsParameters {
            public var previous: String?
            public var next: String?

            public static func fields() -> [String] {
                [CodingKeys.previous, CodingKeys.next]
                    .map(\.stringValue)
            }
        }

        public static func fields() -> [String] {
            [CodingKeys.data.stringValue] + D.fields() +
                [CodingKeys.paging.stringValue] + Page.fields()
        }
    }

    enum Sort: String, Decodable {
        case list_score
        case list_updated_at
        case anime_title
        case anime_start_date
    }

    enum Status: String, Decodable {
        case watching
        case completed
        case on_hold
        case dropped
        case plan_to_watch
    }

    enum Source: String, Decodable {
        case other
        case original
        case manga
        case web_manga
        case digital_manga
        case novel
        case light_novel
        case visual_novel
        case game
        case card_game
        case book
        case picture_book
        case radio
        case music
    }

    struct List<
        D: Decodable & Equatable & FieldsParameters
    >: Decodable, Equatable, FieldsParameters {
        public let node: D
        public let list_status: ListStatus

        public struct ListStatus: Decodable, Equatable, FieldsParameters {
            public let status: Status?
            public let score: Int
            public let num_episodes_watched: Int
            public let is_rewatching: Bool
//            public let start_date: String?
//            public let finish_date: String?
            public let num_times_rewatched: Int?
            public let tags: [String]?
            public let comments: String?
            public let updated_at: String?

            public static func fields() -> [String] {
                [
                    CodingKeys.status,
                    CodingKeys.score,
                    CodingKeys.num_episodes_watched,
                    CodingKeys.is_rewatching,
//                    CodingKeys.start_date,
//                    CodingKeys.finish_date,
                    CodingKeys.num_times_rewatched,
                    CodingKeys.tags,
                    CodingKeys.comments,
                    CodingKeys.updated_at
                ]
                .map(\.stringValue)
            }
        }

        public static func fields() -> [String] {
            [CodingKeys.node.stringValue] + D.fields() +
                [CodingKeys.list_status.stringValue] + ListStatus.fields()
        }
    }

    struct Media: Decodable, Equatable, FieldsParameters {
        public let id: Int
        public let title: String
        public let main_picture: Picture?
        public let num_episodes: Int?
        public let source: Source?
        public let media_type: MediaType?
        public let status: Status?

        public struct Picture: Decodable, Equatable {
            public let large: String?
            public let medium: String
        }

        public enum MediaType: String, Equatable, Decodable {
            case unknown
            case tv
            case ova
            case movie
            case special
            case ona
            case music
        }

        public enum Status: String, Equatable, Decodable {
            case finished_airing
            case currently_airing
            case not_yet_aired
        }

        public static func fields() -> [String] {
            [
                CodingKeys.id,
                CodingKeys.title,
                CodingKeys.main_picture,
                CodingKeys.num_episodes,
                CodingKeys.source,
                CodingKeys.media_type,
                CodingKeys.status
            ]
            .map(\.stringValue)
        }
    }

    typealias AnimeList = List<Media>
}

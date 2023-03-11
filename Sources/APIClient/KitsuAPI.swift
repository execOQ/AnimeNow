//
//  KitsuAPI.swift
//  Anime Now! (iOS)
//
//  Created by ErrorErrorError on 9/29/22.
//

import Foundation
import SharedModels
import SociableWeaver
import Utilities

// MARK: - KitsuEndpoint

public struct KitsuEndpoint<D: Decodable>: Endpoint {
    var base = URL(string: "https://kitsu.io/api").unsafelyUnwrapped
    var path: [CustomStringConvertible] = []
    var query: [Query] = []
    var method: Request<D>.Method = .get
    var headers: [String: CustomStringConvertible]?
}

public extension KitsuEndpoint {
    static func createToken(
        _ username: String,
        _ password: String
    ) -> KitsuEndpoint<KitsuModels.Token> {
        let body = [
            "grant_type": "password",
            "username": username,
            "password": password
        ]
        .map { "\($0.key)=\($0.value)" }
        .joined(separator: "&")
        .data(using: .utf8) ?? .init()

        return .init(
            path: ["oauth", "token"],
            method: .post(body),
            headers: [
                "Content-Type": "application/x-www-form-urlencoded"
            ]
        )
    }

    static func refreshToken(
        _ oldToken: String
    ) -> KitsuEndpoint<KitsuModels.Token> {
        let body = [
            "grant_type": "refresh_token",
            "refresh_token": oldToken
        ]
        .map { "\($0.key)=\($0.value)" }
        .joined(separator: "&")
        .data(using: .utf8) ?? .init()

        return .init(
            path: ["oauth", "token"],
            method: .post(body),
            headers: [
                "Content-Type": "application/x-www-form-urlencoded"
            ]
        )
    }

    static func graphql<Q: KitsuQuery>(
        _ query: Q.Type,
        _ options: Q.QueryOptions,
        _ token: String? = nil
    ) throws -> KitsuEndpoint<Q.Response> {
        let start = Date()
        let query = query.createQuery(options)
        let stop = Date()
        print("Took \(stop.timeIntervalSince(start))s")
        let data = try GraphQL.Paylod(query: query.description).toData()
        var headers = [
            "Content-Type": "application/json",
            "Content-Length": "\(data.count)",
            "Accept": "application/json"
        ]
        token.flatMap { headers["Authorization"] = "Bearer \($0)" }
        return .init(
            path: ["graphql"],
            method: .post(data),
            headers: headers
        )
    }

    static func graphql<Q: KitsuQuery>(
        _ query: Q.Type,
        _ token: String? = nil
    ) throws -> KitsuEndpoint<Q.Response> where Q.QueryOptions == Void {
        try .graphql(query, (), token)
    }
}

public extension Request {
    static func kitsu<D>(_ endpoint: KitsuEndpoint<D>) -> Request<D> {
        endpoint.build()
    }
}

// MARK: - KitsuQuery

public protocol KitsuQuery: GraphQLQuery {}

// MARK: - KitsuModels

public enum KitsuModels {}

// MARK: KitsuModels.CurrentAccountQuery

public extension KitsuModels {
    struct CurrentAccountQuery: KitsuQuery {
        public typealias Response = GraphQL.Response<Self>

        public struct QueryOptions {
            let arguments: CurrentAccount.Argument

            public init(arguments: CurrentAccount.Argument = .init()) {
                self.arguments = arguments
            }
        }

        public let currentAccount: CurrentAccount

        public static func createQuery(_ options: QueryOptions) -> Weave {
            Weave(.query) {
                CurrentAccount.createQueryObject(CodingKeys.currentAccount, options.arguments)
            }
        }
    }

    struct LibraryEntryUpdateProgressByMediaMutation: KitsuQuery {
        public typealias Response = GraphQL.Response<Self>

        public struct QueryOptions: ArgumentValueRepresentable {
            let mediaId: String
            let mediaType: KitsuModels.MediaType
            let progress: Int

            public var argumentValue: String {
                "{ mediaId: \(mediaId), mediaType: \(mediaType.rawValue), progress: \(progress) }"
            }

            public init(
                mediaId: String,
                mediaType: KitsuModels.MediaType = .ANIME,
                progress: Int
            ) {
                self.mediaId = mediaId
                self.mediaType = mediaType
                self.progress = progress
            }
        }

        let libraryEntry: EmptyResponse

        public static func createQuery(_ options: QueryOptions) -> Weave {
            Weave(.mutation) {
                Object(name: "libraryEntry") {
                    Object(name: "updateProgressByMedia") {
                        Object("libraryEntry") {
                            Field("id")
                        }
                    }
                    .argument(key: "input", value: options)
                }
            }
        }
    }

    struct LibraryEntryUpdateStatusByMediaMutation: KitsuQuery {
        public typealias Response = GraphQL.Response<Self>

        public struct QueryOptions: ArgumentValueRepresentable {
            let mediaId: String
            let mediaType: KitsuModels.MediaType
            let status: KitsuModels.LibraryEntry.Status

            public var argumentValue: String {
                "{ mediaId: \(mediaId), mediaType: \(mediaType.rawValue), status: \(status.rawValue) }"
            }

            public init(
                mediaId: String,
                mediaType: KitsuModels.MediaType = .ANIME,
                status: KitsuModels.LibraryEntry.Status
            ) {
                self.mediaId = mediaId
                self.mediaType = mediaType
                self.status = status
            }
        }

        let libraryEntry: EmptyResponse

        public static func createQuery(_ options: QueryOptions) -> Weave {
            Weave(.mutation) {
                Object(name: "libraryEntry") {
                    Object(name: "updateStatusByMedia") {
                        Object("libraryEntry") {
                            Field("id")
                        }
                    }
                    .argument(key: "input", value: options)
                }
            }
        }
    }

    struct LibraryEntryCreateMutation: KitsuQuery {
        public typealias Response = GraphQL.Response<Self>

        public struct QueryOptions: ArgumentValueRepresentable {
            let mediaId: String
            let mediaType: KitsuModels.MediaType
            let status: KitsuModels.LibraryEntry.Status
            let progress: Int

            public var argumentValue: String {
                "{ mediaId: \(mediaId), mediaType: \(mediaType.rawValue), status: \(status.rawValue) progress: \(progress) }"
            }

            public init(
                mediaId: String,
                mediaType: KitsuModels.MediaType = .ANIME,
                status: KitsuModels.LibraryEntry.Status = .CURRENT,
                progress: Int = 0
            ) {
                self.mediaId = mediaId
                self.mediaType = mediaType
                self.progress = progress
                self.status = status
            }
        }

        let libraryEntry: EmptyResponse

        public static func createQuery(_ options: QueryOptions) -> Weave {
            Weave(.mutation) {
                Object(name: "libraryEntry") {
                    Object(name: "create") {
                        Object(name: "libraryEntry") {
                            Field("id")
                        }
                    }
                    .argument(key: "input", value: options)
                }
            }
        }
    }
}

public extension KitsuModels {
    struct Token: Codable {
        public let access_token: String
        public let token_type: String
        public let expires_in: Int
        public let refresh_token: String
        public let scope: String
        public let created_at: Date
    }

    struct CurrentAccount: GraphQLQueryObject {
        public struct Argument {
            let profileArguments: Profile.Argument

            public init(profileArguments: Profile.Argument = .init()) {
                self.profileArguments = profileArguments
            }
        }

        public let profile: Profile

        public static func createQueryObject(
            _ name: String,
            _ argument: Argument
        ) -> Object {
            Object(name: name) {
                Profile.createQueryObject(CodingKeys.profile, argument.profileArguments)
            }
        }
    }

    struct PageInfo: Decodable {
        let endCursor: String?
        let hasNextPage: Bool
        let hasPreviousPage: Bool
        let startCursor: String?

        // swiftlint:disable prefer_self_in_static_references
        static func createQueryObject(
            _ name: CodingKey
        ) -> Object {
            Object(name: name) {
                Field(PageInfo.CodingKeys.endCursor)
                Field(PageInfo.CodingKeys.hasNextPage)
                Field(PageInfo.CodingKeys.hasPreviousPage)
                Field(PageInfo.CodingKeys.startCursor)
            }
        }
    }

    struct MediaProductionConnection: Decodable, Equatable {
        let nodes: [MediaProduction]

        static func createQueryObject(
            _ name: CodingKey
        ) -> Object {
            Object(name: name) {
                MediaProduction.createQueryObject(CodingKeys.nodes)
            }
            .argument(key: "first", value: 20)
        }
    }

    struct MediaProduction: Decodable, Equatable {
        let company: Producer
        let role: Role

        enum Role: String, Decodable, Equatable {
            case PRODUCER
            case LICENSOR
            case STUDIO
            case SERIALIZATION
        }

        static func createQueryObject(
            _ name: CodingKey
        ) -> Object {
            Object(name: name) {
                Producer.createQueryObject(CodingKeys.company)
                Field(CodingKeys.role)
            }
        }
    }

    struct Producer: GraphQLQueryObject, Equatable {
        let name: String

        public static func createQueryObject(
            _ name: String,
            _: Void
        ) -> Object {
            Object(name: name) {
                Field(CodingKeys.name)
            }
        }
    }

    enum MediaType: String, EnumValueRepresentable {
        case ANIME
        case MANGA
    }

    struct Profile: GraphQLQueryObject, Equatable {
        public struct Argument {
            let libraryArguments: Library.Argument?

            public init(libraryArguments: Library.Argument? = nil) {
                self.libraryArguments = libraryArguments
            }
        }

        public let id: String
        public let name: String
        public let about: String?
        public let avatarImage: Image?
        public let bannerImage: Image?
        public let stats: Stats
        public let library: Library?

        public static func createQueryObject(
            _ name: String,
            _ argument: Argument = .init()
        ) -> Object {
            Object(name: name) {
                Field(CodingKeys.id)
                Field(CodingKeys.name)
                Field(CodingKeys.about)
                Image.createQueryObject(CodingKeys.avatarImage)
                Image.createQueryObject(CodingKeys.bannerImage)
                Stats.createQueryObject(CodingKeys.stats)
                if let libraryArguments = argument.libraryArguments {
                    Library.createQueryObject(CodingKeys.library, libraryArguments)
                }
            }
        }

        public struct Stats: GraphQLQueryObject, Equatable {
            public let animeAmountConsumed: Consumed

            public static func createQueryObject(
                _ name: String,
                _: Void
            ) -> Object {
                Object(name: name) {
                    Consumed.createQueryObject(CodingKeys.animeAmountConsumed)
                }
            }

            public struct Consumed: GraphQLQueryObject, Equatable {
                public let id: String
                public let completed: Int
                public let time: Int
                public let units: Int

                public static func createQueryObject(
                    _ name: String,
                    _: Void
                ) -> Object {
                    Object(name: name) {
                        Field(CodingKeys.id)
                        Field(CodingKeys.completed)
                        Field(CodingKeys.time)
                        Field(CodingKeys.units)
                    }
                }
            }
        }
    }

    struct Category: Decodable, Equatable {
        let title: Localization

        static func createQueryObject(
            _ name: CodingKey
        ) -> Object {
            Object(name: name) {
                Field(CodingKeys.title)
            }
        }
    }

    struct Library: GraphQLQueryObject, Equatable {
        public struct Argument {
            let entryArguments: LibraryEntryConnection.Argument

            public init(entryArguments: LibraryEntryConnection.Argument = .init()) {
                self.entryArguments = entryArguments
            }
        }

//        public let all: LibraryEntryConnection
        public let completed: LibraryEntryConnection
        public let current: LibraryEntryConnection
        public let dropped: LibraryEntryConnection
        public let onHold: LibraryEntryConnection
        public let planned: LibraryEntryConnection

        public static func createQueryObject(
            _ name: String,
            _ argument: Argument = .init()
        ) -> Object {
            Object(name: name) {
                LibraryEntryConnection.createQueryObject(CodingKeys.completed, argument.entryArguments)
                LibraryEntryConnection.createQueryObject(CodingKeys.current, argument.entryArguments)
                LibraryEntryConnection.createQueryObject(CodingKeys.dropped, argument.entryArguments)
                LibraryEntryConnection.createQueryObject(CodingKeys.onHold, argument.entryArguments)
                LibraryEntryConnection.createQueryObject(CodingKeys.planned, argument.entryArguments)
            }
        }
    }

    struct LibraryEntryConnection: GraphQLQueryObject, Equatable {
        public struct Argument {
            var mediaType: MediaType
            var first: Int

            public init(
                mediaType: KitsuModels.MediaType = .ANIME,
                first: Int = 20
            ) {
                self.mediaType = mediaType
                self.first = first
            }
        }

        public let nodes: [LibraryEntry]

        public static func createQueryObject(
            _ name: String,
            _ arguments: Argument = .init()
        ) -> Object {
            Object(name: name) {
                LibraryEntry.createQueryObject(CodingKeys.nodes)
            }
            .argument(key: "mediaType", value: arguments.mediaType)
            .argument(key: "first", value: arguments.first)
        }
    }

    struct LibraryEntry: GraphQLQueryObject, Equatable {
        public let id: String
        public let media: Anime
        public let `private`: Bool
        public let progress: Int
        public let rating: Int?
        public let notes: String?
        public let status: Status

        public static func createQueryObject(
            _ name: String,
            _: Void
        ) -> Object {
            Object(name: name) {
                Field(CodingKeys.id)
                Anime.createQueryObject(CodingKeys.media)
                Field(CodingKeys.progress)
                Field(CodingKeys.private)
                Field(CodingKeys.rating)
                Field(CodingKeys.notes)
                Field(CodingKeys.status)
            }
        }

        public enum Status: String, EnumRawValueRepresentable, Decodable {
            case CURRENT
            case PLANNED
            case COMPLETED
            case ON_HOLD
            case DROPPED
        }
    }

    struct Localization: Decodable, Equatable {
        let en: String?
    }

    struct Image: GraphQLQueryObject, Equatable {
        public let blurhash: String?
        public let original: ImageView
        public let views: [ImageView]

        public static func createQueryObject(
            _ name: String,
            _: Void
        ) -> Object {
            Object(name: name) {
                Field(CodingKeys.blurhash)
                ImageView.createQueryObject(CodingKeys.original)
                ImageView.createQueryObject(CodingKeys.views)
            }
        }
    }

    struct ImageView: GraphQLQueryObject, Equatable {
        public let name: String
        public let url: URL
        public let height: Int?
        public let width: Int?

        public static func createQueryObject(
            _ name: String,
            _: Void
        ) -> Object {
            Object(name: name) {
                Field(CodingKeys.name)
                Field(CodingKeys.url)
                Field(CodingKeys.width)
                Field(CodingKeys.height)
            }
        }
    }

    struct Titles: Decodable, Equatable {
        let canonical: String?
        let original: String?
        let preferred: String?
        let romanized: String?
        let translated: String?

        static func createQueryObject(
            _ name: CodingKey,
            _ includePreferred: Bool = true,
            _ includeCanonical: Bool = true
        ) -> Object {
            Object(name: name) {
                Field(CodingKeys.preferred)
                    .include(if: includePreferred)
                Field(CodingKeys.canonical)
                    .include(if: includeCanonical)
                Field(CodingKeys.original)
                Field(CodingKeys.translated)
                Field(CodingKeys.romanized)
            }
        }
    }

    struct MappingConnection: Decodable, Equatable {
        let nodes: [Mapping] // Stub

        static func createQueryObject(
            _ name: CodingKey
        ) -> Object {
            Object(name: name) {
                Mapping.createQueryObject(CodingKeys.nodes)
            }
            .argument(key: "first", value: 20)
        }
    }

    struct Mapping: Decodable, Equatable {
        let id: String
        let externalId: String
        let externalSite: ExternalSite

        enum ExternalSite: String, Decodable {
            case MYANIMELIST_ANIME
            case MYANIMELIST_MANGA
            case MYANIMELIST_CHARACTERS
            case MYANIMELIST_PEOPLE
            case MYANIMELIST_PRODUCERS
            case ANILIST_ANIME
            case ANILIST_MANGA
            case THETVDB
            case THETVDB_SERIES
            case THETVDB_SEASON
            case ANIDB
            case ANIMENEWSNETWORK
            case MANGAUPDATES
            case HULU
            case IMDB_EPISODES
            case AOZORA
            case TRAKT
            case MYDRAMALIST
        }

        static func createQueryObject(
            _ name: CodingKey
        ) -> Object {
            Object(name: name) {
                Field(CodingKeys.id)
                Field(CodingKeys.externalSite)
                Field(CodingKeys.externalId)
            }
        }
    }

    struct Anime: GraphQLQueryObject, Equatable {
        // Media

        let id: String
        let slug: String
        let posterImage: Image?
        let bannerImage: Image?
        let titles: Titles
        let averageRating: Float?
        let averageRatingRank: Int?
        let status: Status
        let userCountRank: Int?
        let ageRating: AgeRating?
        let startDate: String?

        // Anime Only

        let season: ReleaseSeason?
        let totalLength: Int?
        let subtype: Subtype?

        public static func createQueryObject(
            _ name: String,
            _: Void
        ) -> Object {
            Object(name: name) {
                Field(CodingKeys.id)
                Field(CodingKeys.slug)
                Image.createQueryObject(CodingKeys.posterImage)
                Image.createQueryObject(CodingKeys.bannerImage)
                Titles.createQueryObject(CodingKeys.titles)
                Field(CodingKeys.averageRating)
                Field(CodingKeys.averageRatingRank)
                Field(CodingKeys.status)
                Field(CodingKeys.userCountRank)
                Field(CodingKeys.ageRating)
                Field(CodingKeys.startDate)

                InlineFragment("Anime") {
                    Field(CodingKeys.season)
                    Field(CodingKeys.totalLength)
                    Field(CodingKeys.subtype)
                }
            }
        }

        enum Status: String, Decodable, EnumRawValueRepresentable {
            case TBA
            case FINISHED
            case CURRENT
            case UPCOMING
            case UNRELEASED
        }

        enum Subtype: String, Decodable {
            case TV
            case SPECIAL
            case OVA
            case ONA
            case MOVIE
            case MUSIC
        }

        enum ReleaseSeason: String, Decodable {
            case WINTER
            case SPRING
            case SUMMER
            case FALL
        }

        // swiftlint:disable identifier_name
        enum AgeRating: String, Decodable, Equatable {
            case G
            case PG
            case R
            case R18
        }
    }
}

// MARK: - Converters

public extension KitsuModels {
    static func sortBasedOnAvgRank(animes: [KitsuModels.Anime]) -> [KitsuModels.Anime] {
        animes.sorted { lhs, rhs in
            if let lhsRank = lhs.averageRatingRank, let rhsRank = rhs.averageRatingRank {
                return lhsRank < rhsRank
            } else if lhs.averageRatingRank != nil, rhs.averageRatingRank == nil {
                return true
            } else {
                return false
            }
        }
    }

    static func sortBasedOnUserRank(animes: [KitsuModels.Anime]) -> [KitsuModels.Anime] {
        animes.sorted { lhs, rhs in
            if let lhsRank = lhs.userCountRank, let rhsRank = rhs.userCountRank {
                return lhsRank < rhsRank
            } else if lhs.userCountRank != nil, rhs.userCountRank == nil {
                return true
            } else {
                return false
            }
        }
    }

    static func convert(from animes: [KitsuModels.Anime]) -> [SharedModels.Anime] {
        animes.compactMap(KitsuModels.convert)
    }

    static func convert(from anime: KitsuModels.Anime) -> SharedModels.Anime? {
        if anime.subtype == .MUSIC {
            return nil
        }

        let posterImageOriginal: [ImageSize]
        let bannerImageOriginal: [ImageSize]

        if let url = anime.posterImage?.original.url {
            posterImageOriginal = [.original(url)]
        } else {
            posterImageOriginal = []
        }

        if let url = anime.posterImage?.original.url {
            bannerImageOriginal = [.original(url)]
        } else {
            bannerImageOriginal = []
        }

        let posterImageSizes = (anime.posterImage?.views ?? []).compactMap(convert(from:)) + posterImageOriginal
        let coverImageSizes = (anime.bannerImage?.views ?? []).compactMap(convert(from:)) + bannerImageOriginal

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy/MM/dd"

        return SharedModels.Anime(
            id: anime.id.hashValue,
            malId: nil,
            title: anime.titles.translated ?? anime.titles.romanized ?? anime.titles.canonical ?? anime.titles
                .original ?? "Untitled",
            description: "Anime description is not available.",
            posterImage: .init(posterImageSizes),
            coverImage: .init(coverImageSizes),
            categories: [],
            status: .init(rawValue: anime.status.rawValue.lowercased()) ?? .upcoming,
            format: anime.subtype == .MOVIE ? .movie : .tv,
            releaseYear: Int(dateFormatter.date(from: anime.startDate ?? "")?.getYear() ?? ""),
            avgRating: nil
        )
    }

    static func convert(from imageView: KitsuModels.ImageView) -> SharedModels.ImageSize? {
        let url = imageView.url

        let name = imageView.name

        if name == "tiny" {
            return ImageSize.tiny(url)
        } else if name == "small" {
            return ImageSize.small(url)
        } else if name == "medium" {
            return ImageSize.medium(url)
        } else if name == "large" {
            return ImageSize.large(url)
        } else {
            // Huh????
            return nil
        }
    }
}

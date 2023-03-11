//
//  AniListAPI.swift
//
//
//  Created by ErrorErrorError on 9/28/22.
//

import AuthenticationClient
import ComposableArchitecture
import Foundation
import SharedModels
import SociableWeaver
import Utilities

// MARK: - AniListEndpoint

public struct AniListEndpoint<D: Decodable>: Endpoint {
    var base = URL(string: "https://graphql.anilist.co").unsafelyUnwrapped
    var query: [Query] = []
    var path: [CustomStringConvertible] = []
    var method: Request<D>.Method
    var headers: [String: CustomStringConvertible]?
}

public extension AniListEndpoint {
    static func graphql<Q: GraphQLQuery & AniListQuery>(
        _ query: Q.Type,
        _ options: Q.QueryOptions,
        _ token: String? = nil
    ) throws -> AniListEndpoint<Q.Response> {
        let query = query.createQuery(options)
        let data = try GraphQL.Paylod(query: query.description).toData()
        var headers = [
            "Content-Type": "application/json",
            "Content-Length": "\(data.count)",
            "Accept": "application/json"
        ]
        token.flatMap { headers["Authorization"] = "Bearer \($0)" }
        return .init(
            method: .post(data),
            headers: headers
        )
    }

    static func graphql<Q: AniListQuery>(
        _ query: Q.Type,
        _ token: String? = nil
    ) throws -> AniListEndpoint<Q.Response> where Q.QueryOptions == Void {
        try .graphql(query, (), token)
    }
}

// MARK: - AniList + Request4

public extension Request {
    static func anilist<D: Decodable>(_ endpoint: AniListEndpoint<D>) -> Request<D> {
        endpoint.build()
    }
}

// MARK: - AniListModels

public enum AniListModels {}

// MARK: - AniList + Converters

public extension AniListModels {
    static func convert(from medias: [Media]) -> [Anime] {
        medias.compactMap { media in
            convert(from: media)
        }
    }

    static func convert(from media: Media) -> Anime {
        var coverImages: [ImageSize] = []

        if let imageStr = media.coverImage.extraLarge, let url = URL(string: imageStr) {
            coverImages.append(.large(url))
        }

        if let imageStr = media.coverImage.large, let url = URL(string: imageStr) {
            coverImages.append(.medium(url))
        }

        if let imageStr = media.coverImage.medium, let url = URL(string: imageStr) {
            coverImages.append(.small(url))
        }

        var posterImage: [ImageSize] = []
        if let imageStr = media.bannerImage, let url = URL(string: imageStr) {
            posterImage.append(.original(url))
        }

        let format: Anime.Format

        switch media.format {
        case .MOVIE:
            format = .movie
        case .TV:
            format = .tv
        case .TV_SHORT:
            format = .tvShort
        case .OVA:
            format = .ova
        case .ONA:
            format = .ona
        case .SPECIAL:
            format = .special
        }

        let status: Anime.Status

        switch media.status {
        case .FINISHED:
            status = .finished
        case .RELEASING:
            status = .current
        case .NOT_YET_RELEASED:
            status = .upcoming
        case .CANCELLED:
            status = .unreleased
        case .HIATUS:
            status = .tba
        }

        let averageScore: Double?

        if let averageRating = media.averageScore {
            averageScore = Double(averageRating) / 100.0
        } else {
            averageScore = nil
        }

        return Anime(
            id: media.id,
            malId: media.idMal,
            title: media.title.english ?? media.title.romaji ?? media.title.native ?? "Untitled",
            description: media.description?.trimHTMLTags() ?? "No description",
            posterImage: coverImages,
            coverImage: posterImage,
            categories: media.genres.prefix(3).sorted(),
            status: status,
            format: format,
            releaseYear: media.startDate.year,
            avgRating: averageScore
        )
    }
}

// MARK: - PageResponseObject

public protocol PageResponseObject {
    static var pageResponseName: String { get }
}

// MARK: - AniListQuery

public protocol AniListQuery: GraphQLQuery {}

public extension AniListModels {
    typealias MediaPageQuery = PageQuery<Self.Media>

    struct PageQuery<O: GraphQLQueryObject & PageResponseObject>: AniListQuery {
        public typealias Response = GraphQL.Response<PageResponse<Self>>

        public enum QueryArgument: DefaultArguments {
            case page(Int = 1)
            case perPage(Int = 25)

            public static var defaultArgs: [QueryArgument] { [.page(), .perPage()] }
        }

        public struct QueryOptions {
            public var arguments: [QueryArgument]
            public var itemArguments: O.Argument

            public init(
                arguments: [QueryArgument] = .defaultArgs,
                itemArguments: O.Argument
            ) {
                self.arguments = arguments
                self.itemArguments = itemArguments
            }
        }

        public let pageInfo: AniListModels.PageInfo
        public let items: [O]

        public enum CodingKeys: CodingKey {
            case pageInfo
            case items

            public init?(stringValue: String) {
                if stringValue == Self.pageInfo.stringValue {
                    self = .pageInfo
                } else if stringValue == Self.items.stringValue {
                    self = .items
                } else {
                    return nil
                }
            }

            public var stringValue: String {
                switch self {
                case .pageInfo:
                    return "pageInfo"
                case .items:
                    return O.pageResponseName
                }
            }
        }

        public static func createQuery(
            _ options: QueryOptions
        ) -> Weave {
            Weave(.query) {
                var obj = Object(name: "Page") {
                    O.createQueryObject(CodingKeys.items, options.itemArguments)
                    AniListModels.PageInfo.createQueryObject(CodingKeys.pageInfo)
                }
                .caseStyle(.pascalCase)

                for argument in options.arguments {
                    switch argument {
                    case let .page(int):
                        obj = obj.argument(key: "page", value: int)
                    case let .perPage(int):
                        obj = obj.argument(key: "perPage", value: int)
                    }
                }
                return obj
            }
        }
    }

    struct Viewer: AniListQuery {
        public typealias Response = GraphQL.Response<Self>

        // swiftlint:disable identifier_name
        public let Viewer: User

        public static func createQuery(_: Void = ()) -> Weave {
            Weave(.query) {
                AniListModels.User.createQueryObject(CodingKeys.Viewer)
                    .caseStyle(.pascalCase)
            }
        }
    }

    struct MediaListCollectionQuery: AniListQuery {
        public typealias Response = GraphQL.Response<Self>

        public let MediaListCollection: MediaListCollection

        public struct QueryArgument {
            let userId: Int
            let type: Media.MediaType

            public init(userId: Int, type: Media.MediaType = .ANIME) {
                self.userId = userId
                self.type = type
            }
        }

        public static func createQuery(_ options: QueryArgument) -> Weave {
            Weave(.query) {
                AniListModels.MediaListCollection.createQueryObject(CodingKeys.MediaListCollection)
                    .argument(key: "userId", value: options.userId)
                    .argument(key: "type", value: options.type)
            }
        }
    }

    struct MediaListQuery: AniListQuery {
        public typealias Response = GraphQL.Response<Self>

        public let MediaList: MediaList

        public struct QueryOptions {
            let userId: Int
            let mediaId: Int

            public init(
                userId: Int,
                mediaId: Int
            ) {
                self.userId = userId
                self.mediaId = mediaId
            }
        }

        public static func createQuery(_ options: QueryOptions) -> Weave {
            Weave(.query) {
                AniListModels.MediaList.createQueryObject(CodingKeys.MediaList)
                    .argument(key: "userId", value: options.userId)
                    .argument(key: "mediaId", value: options.mediaId)
                    .caseStyle(.pascalCase)
            }
        }
    }

    struct SaveMediaListEntryMutation: AniListQuery {
        public typealias Response = GraphQL.Response<Self>

        public let SaveMediaListEntry: MediaList

        public struct QueryOptions {
            let id: Int?
            let mediaId: Int
            let status: MediaList.Status?
            let progress: Int?

            public init(
                id: Int? = nil,
                mediaId: Int,
                status: MediaList.Status? = nil,
                progress: Int? = nil
            ) {
                self.id = id
                self.mediaId = mediaId
                self.progress = progress
                self.status = status
            }
        }

        public static func createQuery(_ options: QueryOptions) -> Weave {
            Weave(.mutation) {
                AniListModels.MediaList.createQueryObject(CodingKeys.SaveMediaListEntry)
                    .argument(key: "id", value: options.id)
                    .argument(key: "mediaId", value: options.mediaId)
                    .argument(key: "progress", value: options.progress)
                    .argument(key: "status", value: options.status)
                    .caseStyle(.pascalCase)
            }
        }
    }
}

// MARK: - GraphQL Models

public extension AniListModels {
    struct PageResponse<T: Decodable>: Decodable {
        // swiftlint:disable identifier_name
        public let Page: T
    }

    struct PageInfo: GraphQLQueryObject {
        public typealias Argument = Void

        let total: Int
        let perPage: Int
        let currentPage: Int
        let lastPage: Int
        let hasNextPage: Bool

        public static func createQueryObject(_ name: String, _: Void) -> Object {
            Object(name: name) {
                Field(CodingKeys.total)
                Field(CodingKeys.perPage)
                Field(CodingKeys.currentPage)
                Field(CodingKeys.lastPage)
                Field(CodingKeys.hasNextPage)
            }
        }
    }

    struct FuzzyDate: GraphQLQueryObject, Equatable {
        public typealias Argument = Void

        let year: Int?
        let month: Int?
        let day: Int?

        public static func createQueryObject(_ name: String, _: Void) -> Object {
            Object(name: name) {
                Field(CodingKeys.year)
                Field(CodingKeys.month)
                Field(CodingKeys.day)
            }
        }
    }

    struct MediaResponse: Decodable {
        public let Media: Media
    }

    struct MediaListCollection: GraphQLQueryObject, Equatable {
        public let lists: [MediaListGroup]
        public let user: User
        public let hasNextChunk: Bool

        public static func createQueryObject(
            _ name: String,
            _: Void
        ) -> Object {
            Object(name: name) {
                MediaListGroup.createQueryObject(CodingKeys.lists)
                User.createQueryObject(CodingKeys.user)
                Field(CodingKeys.hasNextChunk)
            }
            .caseStyle(.pascalCase)
        }
    }

    struct MediaListGroup: GraphQLQueryObject, Equatable {
        public let entries: [MediaList]
        public let name: String
        @Defaultable<True>
        public var isCustomList: Bool
        public let status: MediaList.Status?

        public static func createQueryObject(
            _ name: String,
            _: Void
        ) -> Object {
            Object(name: name) {
                MediaList.createQueryObject(CodingKeys.entries)
                Field(CodingKeys.name)
                Field(CodingKeys.isCustomList)
                Field(CodingKeys.status)
            }
        }
    }

    struct MediaList: GraphQLQueryObject, Equatable {
        public let id: Int
        public let userId: Int
        public let mediaId: Int
        public let status: Status?
        public let progress: Int?
        public let `repeat`: Int?
        public let priority: Int?
        @Defaultable<False>
        public var `private`: Bool
        public let startedAt: FuzzyDate?
        public let completedAt: FuzzyDate?
        public let createdAt: Int?
        public let updatedAt: Int?
        public let media: Media?

        public enum Status: String, Decodable, EnumValueRepresentable, Equatable {
            case CURRENT
            case PLANNING
            case COMPLETED
            case DROPPED
            case PAUSED
            case REPEATING
        }

        public static func createQueryObject(
            _ name: String,
            _: Void
        ) -> Object {
            Object(name: name) {
                Field(CodingKeys.id)
                Field(CodingKeys.userId)
                Field(CodingKeys.mediaId)
                Field(CodingKeys.status)
                Field(CodingKeys.progress)
                Field(CodingKeys.repeat)
                Field(CodingKeys.priority)
                Field(CodingKeys.private)
                FuzzyDate.createQueryObject(CodingKeys.startedAt)
                FuzzyDate.createQueryObject(CodingKeys.completedAt)
                Field(CodingKeys.createdAt)
                Field(CodingKeys.updatedAt)
                Media.createQueryObject(CodingKeys.media, .init(filters: []))
            }
        }
    }

    struct User: GraphQLQueryObject, Equatable {
        public typealias Argument = Void

        public let id: Int
        public let name: String
        public let avatar: Avatar?
        public let bannerImage: String?
        public let statistics: StatisticType?

        public struct Avatar: GraphQLQueryObject, Equatable {
            public let large: String?
            public let medium: String?

            public static func createQueryObject(_ name: String, _: Void) -> Object {
                Object(name: name) {
                    Field(CodingKeys.large)
                    Field(CodingKeys.medium)
                }
            }
        }

        public struct StatisticType: GraphQLQueryObject, Equatable {
            public let anime: Statistic

            public struct Statistic: GraphQLQueryObject, Equatable {
                @Defaultable<Zero>
                public var count: Int
                @Defaultable<Zero>
                public var episodesWatched: Int
                @Defaultable<Zero>
                public var minutesWatched: Int

                public static func createQueryObject(_ name: String, _: Void) -> Object {
                    Object(name: name) {
                        Field(CodingKeys.count)
                        Field(CodingKeys.episodesWatched)
                        Field(CodingKeys.minutesWatched)
                    }
                }
            }

            public static func createQueryObject(_ name: String, _: Void) -> Object {
                Object(name: name) {
                    Statistic.createQueryObject(CodingKeys.anime)
                }
            }
        }

        public static func createQueryObject(_ name: String, _: Void) -> Object {
            Object(name: name) {
                Field(CodingKeys.id)
                Field(CodingKeys.name)
                Avatar.createQueryObject(CodingKeys.avatar)
                Field(CodingKeys.bannerImage)
                StatisticType.createQueryObject(CodingKeys.statistics)
            }
        }
    }

    struct Media: GraphQLQueryObject, PageResponseObject, AniListQuery, Equatable {
        public typealias Response = GraphQL.Response<MediaResponse>

        public static var pageResponseName: String { "media" }

        public let id: Int
        public let idMal: Int?
        public let title: Title
        public let type: MediaType
        public let format: Format
        public let status: Status
        public let description: String?
        public let seasonYear: Int?
        public let coverImage: MediaCoverImage
        public let bannerImage: String?
        public let startDate: FuzzyDate
        public let averageScore: Int?
        public let genres: [String]

        public enum Filter: DefaultArguments {
            case id(Int)
            case idIn([Int])
            case isAdult(Bool = false)
            case type(MediaType = .ANIME)
            case formatIn([Format] = Format.allCases)
            case sort([TrendSort])
            case status(Status)
            case statusIn([Status])
            case statusNot(Status)
            case statusNotIn([Status])
            case search(String)

            public static let defaultArgs: [Self] = {
                [.isAdult(), .type(), .formatIn()]
            }()
        }

        public struct Argument {
            let filters: [Filter]

            public init(filters: [AniListModels.Media.Filter] = .defaultArgs) {
                self.filters = filters
            }
        }

        public static func createQueryObject(
            _ name: String,
            _ arguments: Argument = .init()
        ) -> Object {
            var obj = Object(name: name) {
                Field(CodingKeys.id)
                Field(CodingKeys.idMal)
                Title.createQueryObject(CodingKeys.title)
                Field(CodingKeys.type)
                Field(CodingKeys.format)
                Field(CodingKeys.status)
                Field(CodingKeys.description)
                Field(CodingKeys.seasonYear)
                MediaCoverImage.createQueryObject(CodingKeys.coverImage)
                Field(CodingKeys.bannerImage)
                FuzzyDate.createQueryObject(CodingKeys.startDate)
                Field(CodingKeys.averageScore)
                Field(CodingKeys.genres)
            }

            for argument in arguments.filters {
                switch argument {
                case let .id(id):
                    obj = obj.argument(key: "id", value: id)
                case let .idIn(ids):
                    obj = obj.argument(key: "id_in", value: ids)
                case let .isAdult(bool):
                    obj = obj.argument(key: "isAdult", value: bool)
                case let .type(mediaType):
                    obj = obj.argument(key: "type", value: mediaType)
                case let .formatIn(formats):
                    obj = obj.argument(key: "format_in", value: formats)
                case let .sort(sort):
                    obj = obj.argument(key: "sort", value: sort)
                case let .search(query):
                    obj = obj.argument(key: "search", value: query)
                case let .status(status):
                    obj = obj.argument(key: "status", value: status)
                case let .statusIn(status):
                    obj = obj.argument(key: "status_in", value: status)
                case let .statusNot(status):
                    obj = obj.argument(key: "status_not", value: status)
                case let .statusNotIn(status):
                    obj = obj.argument(key: "status_not_in", value: status)
                }
            }
            return obj
        }

        public static func createQuery(
            _ arguments: Argument = .init()
        ) -> Weave {
            enum CodingKeys: CodingKey {
                case Media
            }

            return Weave(.query) {
                Self.createQueryObject(CodingKeys.Media, arguments)
                    .caseStyle(.pascalCase)
            }
        }

        public enum TrendSort: EnumValueRepresentable {
            case ID
            case ID_DESC
            case MEDIA_ID
            case MEDIA_ID_DESC
            case DATE
            case DATE_DESC
            case SCORE
            case SCORE_DESC
            case POPULARITY
            case POPULARITY_DESC
            case TRENDING
            case TRENDING_DESC
            case EPISODE
            case EPISODE_DESC
        }

        public struct MediaCoverImage: GraphQLQueryObject, Equatable {
            let extraLarge: String?
            let large: String?
            let medium: String?

            public static func createQueryObject(
                _ name: String,
                _: Void
            ) -> Object {
                Object(name: name) {
                    Field(CodingKeys.extraLarge)
                    Field(CodingKeys.large)
                    Field(CodingKeys.medium)
                }
            }
        }

        public enum Status: String, Decodable, EnumValueRepresentable, Equatable {
            case FINISHED
            case RELEASING
            case NOT_YET_RELEASED
            case CANCELLED
            case HIATUS
        }

        public enum Format: String, Decodable, EnumValueRepresentable, CaseIterable, Equatable {
            case TV
            case TV_SHORT
            case MOVIE
            case SPECIAL
            case OVA
            case ONA
        }

        public enum MediaType: String, Decodable, EnumRawValueRepresentable, Equatable {
            case ANIME
            case MANGA
        }

        public struct Title: GraphQLQueryObject, Equatable {
            public let romaji: String?
            public let english: String?
            public let native: String?
            public let userPreferred: String?

            public static func createQueryObject(
                _ name: String,
                _: Void
            ) -> Object {
                Object(name: name) {
                    Field(CodingKeys.romaji)
                    Field(CodingKeys.english)
                    Field(CodingKeys.native)
                    Field(CodingKeys.userPreferred)
                }
            }
        }
    }
}

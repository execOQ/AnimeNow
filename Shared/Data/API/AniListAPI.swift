//
//  Anilist.swift
//  Anime Now! (iOS)
//
//  Created by Erik Bautista on 9/28/22.
//

import Foundation
import URLRouting
import SociableWeaver

final class AniListAPI: APIRoute {
    enum Endpoint: Equatable {
        case graphql(GraphQL.Paylod)
    }

    var baseURL: URL {
        URL(string: "https://graphql.anilist.co")!
    }

    let router: AnyParserPrinter<URLRequestData, Endpoint> = {
        OneOf {
            Route(.case(Endpoint.graphql)) {
                Method.post
                Body(.json(GraphQL.Paylod.self))
            }
        }
        .eraseToAnyParserPrinter()
    }()

    func applyHeaders(request: inout URLRequest) {
        let bodyCount = request.httpBody?.count ?? 0
        let requestHeaders = [
            "Content-Type": "application/json",
            "Content-Length": "\(bodyCount)"
        ]

        for header in requestHeaders {
            request.addValue(header.value, forHTTPHeaderField: header.key)
        }
    }
}

extension AniListAPI {
    static func convert(from medias: [Media]) -> [Anime] {
        medias.compactMap { media in
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
            case .some(.MOVIE):
                format = .movie
            case .some(.TV_SHORT), .some(Media.Format.TV), .some(.OVA), .some(.SPECIAL):
                format = .tv
            default:
                return nil
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
            return Anime(
                id: media.id,
                title: media.title.english ?? media.title.romaji ?? media.title.native ?? "Untitled",
                description: media.description?.trimHTMLTags() ?? "No description",
                posterImage: coverImages,
                coverImage: posterImage,
                categories: [],
                status: status,
                format: format,
                studios: [],
                releaseYear: media.startDate.year
            )
        }
    }
}

extension AniListAPI {
    struct PageResponse<T: Decodable>: Decodable {
        let Page: T
    }

    struct PageInfo: Decodable, GraphQLQueryObject {
        let total: Int
        let perPage: Int
        let currentPage: Int
        let lastPage: Int
        let hasNextPage: Bool

        static func createQueryObject(_ name: CodingKey) -> Object {
            Object(name) {
                Field(CodingKeys.total)
                Field(CodingKeys.perPage)
                Field(CodingKeys.currentPage)
                Field(CodingKeys.lastPage)
                Field(CodingKeys.hasNextPage)
            }
        }
    }

    struct MediaPage: Decodable {
        let pageInfo: PageInfo
        let media: [Media]

        enum ArgumentOptions {
            case page(Int = 1)
            case perPage(Int = 25)

            static let defaults: [ArgumentOptions] = {
                [.page(), .perPage()]
            }()
        }

        static func createQuery(
            _ arguments: [ArgumentOptions] = ArgumentOptions.defaults,
            _ mediaArguments: [Media.ArgumentOptions] = Media.ArgumentOptions.defaults
        ) -> Weave {
            Weave(.query) {
                var obj = Object("Page") {
                    Media.createQueryObject(CodingKeys.media, mediaArguments)
                    PageInfo.createQueryObject(CodingKeys.pageInfo)
                }
                    .caseStyle(.pascalCase)

                for argument in arguments {
                    switch argument {
                    case .page(let int):
                        obj = obj.argument(key: "page", value: int)
                    case .perPage(let int):
                        obj = obj.argument(key: "perPage", value: int)
                    }
                }
                return "{ \(obj.description) }"
            }
        }
    }

    struct FuzzyDate: Decodable, GraphQLQueryObject {
        let year: Int?
        let month: Int?
        let day: Int?

        static func createQueryObject(
            _ name: CodingKey
        ) -> Object {
            Object(name) {
                Field(CodingKeys.year)
                Field(CodingKeys.month)
                Field(CodingKeys.day)
            }
        }
    }

    struct Media: Decodable {
        let id: Int
        let title: Title
        let type: MType
        let format: Format?
        let status: Status
        let description: String?
        let seasonYear: Int?
        let coverImage: MediaCoverImage
        let bannerImage: String?
        let startDate: FuzzyDate

        enum ArgumentOptions {
            case isAdult(Bool = false)
            case type(MType = .ANIME)
            case sort([TrendSort])
            case status(Status)
            case statusIn([Status])
            case statusNot(Status)
            case statusNotIn([Status])
            case search(String)

            static let defaults: [ArgumentOptions] = {
                [.isAdult(), .type()]
            }()
        }

        static func createQueryObject(
            _ name: CodingKey,
            _ arguments: [ArgumentOptions] = ArgumentOptions.defaults
        ) -> Object {
            var obj = Object(name) {
                Field(CodingKeys.id)
                Title.createQueryObject(CodingKeys.title)
                Field(CodingKeys.type)
                Field(CodingKeys.format)
                Field(CodingKeys.status)
                Field(CodingKeys.description)
                Field(CodingKeys.seasonYear)
                MediaCoverImage.createQueryObject(CodingKeys.coverImage)
                Field(CodingKeys.bannerImage)
                FuzzyDate.createQueryObject(CodingKeys.startDate)
            }

            for argument in arguments {
                switch argument {
                case .isAdult(let bool):
                    obj = obj.argument(key: "isAdult", value: bool)
                case .type(let mediaType):
                    obj = obj.argument(key: "type", value: mediaType)
                case .sort(let sort):
                    obj = obj.argument(key: "sort", value: sort)
                case .search(let query):
                    obj = obj.argument(key: "search", value: query)
                case .status(let status):
                    obj = obj.argument(key: "status", value: status)
                case .statusIn(let status):
                    obj = obj.argument(key: "status_in", value: status)
                case .statusNot(let status):
                    obj = obj.argument(key: "status_not", value: status)
                case .statusNotIn(let status):
                    obj = obj.argument(key: "status_not_in", value: status)
                }
            }
            return obj
        }

        enum TrendSort: EnumValueRepresentable {
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
        
        struct MediaCoverImage: Decodable {
            let extraLarge: String?
            let large: String?
            let medium: String?

            static func createQueryObject(
                _ name: CodingKey
            ) -> Object {
                Object(name) {
                    Field(CodingKeys.extraLarge)
                    Field(CodingKeys.large)
                    Field(CodingKeys.medium)
                }
            }
        }

        enum Status: String, Decodable, EnumValueRepresentable {
            case FINISHED
            case RELEASING
            case NOT_YET_RELEASED
            case CANCELLED
            case HIATUS
        }

        enum Format: String, Decodable {
            case TV
            case TV_SHORT
            case MOVIE
            case SPECIAL
            case OVA
            case ONA
            case MUSIC
            case MANGA
            case NOVEL
            case ONE_SHOT
        }

        enum MType: String, Decodable, EnumRawValueRepresentable {
            case ANIME
            case MANGA
        }

        struct Title: Decodable {
            let romaji: String?
            let english: String?
            let native: String?
            let userPreferred: String?
        
            static func createQueryObject(
                _ name: CodingKey
            ) -> Object {
                Object(name) {
                    Field(CodingKeys.romaji)
                    Field(CodingKeys.english)
                    Field(CodingKeys.native)
                    Field(CodingKeys.userPreferred)
                }
            }
        }
    }
}
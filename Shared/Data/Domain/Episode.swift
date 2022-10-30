//
//  Episode.swift
//  Anime Now!
//
//  Created by ErrorErrorError on 9/4/22.
//

import Foundation

protocol EpisodeRepresentable  {
    var number: Int { get }
    var title: String { get }
    var thumbnail: ImageSize? { get }
    var providers: [Provider] { get }

    func isEqualTo(_ item: EpisodeRepresentable) -> Bool
    func asRepresentable() -> AnyEpisodeRepresentable
}

extension EpisodeRepresentable where Self: Equatable {
    func isEqualTo(_ item: EpisodeRepresentable) -> Bool {
        guard let item = item as? Self else { return false }
        return self == item
    }
}

extension EpisodeRepresentable {
    func asRepresentable() -> AnyEpisodeRepresentable {
        .init(self)
    }
}

struct AnyEpisodeRepresentable: EpisodeRepresentable, Identifiable {
    private let episode: EpisodeRepresentable

    var id: Int {
        episode.number
    }

    var number: Int {
        episode.number
    }

    var title: String {
        episode.title
    }

    var thumbnail: ImageSize? {
        episode.thumbnail
    }

    var providers: [Provider] {
        episode.providers
    }

    init(_ episode: EpisodeRepresentable) {
        self.episode = episode
    }
}

extension AnyEpisodeRepresentable: Equatable {
    static func == (lhs: AnyEpisodeRepresentable, rhs: AnyEpisodeRepresentable) -> Bool {
        lhs.episode.isEqualTo(rhs.episode)
    }
}

struct Episode: EpisodeRepresentable, Hashable, Identifiable {
    var id: Int { number }
    let title: String
    let number: Int
    let description: String
    let thumbnail: ImageSize?

    var providers = [Provider]()
}

enum Provider: Hashable, Identifiable, CustomStringConvertible, Codable {
    case gogoanime(id: String, dub: Bool)
    case zoro(id: String, dub: Bool = false)
    case offline(url: URL)

    var id: String? {
        switch self {
        case .gogoanime(let id, _), .zoro(let id, _):
            return id
        default:
            return nil
        }
    }

    var dub: Bool? {
        switch self {
        case .gogoanime(_, let dub), .zoro(_, let dub):
            return dub
        default:
            return nil
        }
    }

    var description: String {
        switch self {
        case .gogoanime:
            return "Gogoanime"
        case .zoro:
            return "Zoro"
        case .offline:
            return "Offline"
        }
    }
}

extension Episode {
//    var lengthFormatted: String {
//        guard let length = length else { return "" }
//        let hours = length / 3600
//        let minutes = (length % 3600) / 60
//        let seconds = (length % 3600) % 60
//
//        var retVal: [String] = []
//
//        if hours > 0 {
//            retVal += ["\(hours) h"]
//        }
//
//        if minutes > 0 {
//            retVal += ["\(minutes) m"]
//        }
//
//        if seconds > 0 && minutes == 0 {
//            retVal += ["\(seconds) s"]
//        }
//
//        return retVal.joined(separator: " ")
//    }

//    var episodeNumberLengthFormat: String {
//        "E\(number)" + (length != nil ? " \u{2022} \(lengthFormatted)" : "")
//    }
}

extension Episode {
    static let empty = Episode(
        title: "",
        number: 0,
        description: "",
        thumbnail: nil
    )

    static let placeholder = Episode(
        title: "Placeholder",
        number: 0,
        description: "Placeholder",
        thumbnail: nil
    )

    static let demoEpisodes: [Episode] = [
        .init(
            title: "Homecoming",
            number: 1,
            description: "An older and stronger Naruto returns from his two and a half years of training with Jiraiya. When he gets back he finds that many things have changed since he left. From Konohamaru becoming a Gennin and being under the supervision of Ebisu to Tsunade's, the Fifth Hokage, being added to the great stone faces. Now the tasks of starting things where they were left has begun. And what new danger does Jiraiya know about?",
            thumbnail: .original(URL(string: "https://artworks.thetvdb.com/banners/episodes/79824/320623.jpg")!),
            providers: [.gogoanime(id: "12345", dub: false), .gogoanime(id: "123456", dub: true)]
        ),
        .init(
            title: "Homecoming 2",
            number: 2,
            description: "An older and stronger Naruto returns from his two and a half years of training with Jiraiya. When he gets back he finds that many things have changed since he left. From Konohamaru becoming a Gennin and being under the supervision of Ebisu to Tsunade's, the Fifth Hokage, being added to the great stone faces. Now the tasks of starting things where they were left has begun. And what new danger does Jiraiya know about?",
            thumbnail: .original(URL(string: "https://artworks.thetvdb.com/banners/episodes/79824/320623.jpg")!)
        )
    ]
}

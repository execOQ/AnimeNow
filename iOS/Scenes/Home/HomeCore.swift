//
//  HomeCore.swift
//  Anime Now!
//
//  Created Erik Bautista on 9/4/22.
//  Copyright © 2022. All rights reserved.
//

import Foundation
import ComposableArchitecture
import SwiftUI

enum HomeCore {
    typealias LoadableAnime = LoadableState<IdentifiedArrayOf<Anime>>
    typealias LoadableEpisodes = LoadableState<IdentifiedArrayOf<EpisodeInfoWithAnime>>

    struct State: Equatable {
        var topTrendingAnime: LoadableAnime = .idle
        var topAiringAnime: LoadableAnime = .idle
        var topUpcomingAnime: LoadableAnime = .idle
        var highestRatedAnime: LoadableAnime = .idle
        var mostPopularAnime: LoadableAnime = .idle
        var resumeWatching: LoadableEpisodes = .idle
    }

    enum Action: Equatable, BindableAction {
        case onAppear
        case animeTapped(Anime)
        case resumeWatchingTapped(EpisodeInfoWithAnime)
        case fetchedAnime(keyPath: WritableKeyPath<State, LoadableAnime>, result: Result<[Anime], EquatableError>)
        case fetchedAnimesInDB([AnimeStore])
        case fetchResumeWatchingAnimes([EpisodeInfoWithAnimeId])
        case fetchedAnimeForResumeWatching(Result<[EpisodeInfoWithAnime], EquatableError>)
        case binding(BindingAction<HomeCore.State>)
    }

    struct Environment {
        let animeClient: AnimeClient
        let mainQueue: AnySchedulerOf<DispatchQueue>
        let mainRunLoop: AnySchedulerOf<RunLoop>
        let repositoryClient: RepositoryClient
    }
}

extension HomeCore.State {
    var isLoading: Bool {
        !topTrendingAnime.hasInitialized || topTrendingAnime.isLoading ||
        !topAiringAnime.hasInitialized || topAiringAnime.isLoading ||
        !topUpcomingAnime.hasInitialized || topUpcomingAnime.isLoading ||
        !highestRatedAnime.hasInitialized || highestRatedAnime.isLoading ||
        !mostPopularAnime.hasInitialized || mostPopularAnime.isLoading ||
        !resumeWatching.hasInitialized || resumeWatching.isLoading
    }

    var hasInitialized: Bool {
        topTrendingAnime.hasInitialized &&
        topAiringAnime.hasInitialized &&
        topUpcomingAnime.hasInitialized &&
        highestRatedAnime.hasInitialized &&
        mostPopularAnime.hasInitialized &&
        resumeWatching.hasInitialized
    }
}

extension HomeCore {
    static let reducer = Reducer<HomeCore.State, HomeCore.Action, HomeCore.Environment>.combine(
        .init { state, action, environment in
            switch (action) {
            case .onAppear:
                guard !state.hasInitialized else {
                    break
                }
                state.topTrendingAnime = .loading
                state.topAiringAnime = .loading
                state.topUpcomingAnime = .loading
                state.highestRatedAnime = .loading
                state.mostPopularAnime = .loading
                state.resumeWatching = .loading
                return .merge(
                    environment.animeClient.getTopTrendingAnime()
                        .receive(on: environment.mainQueue)
                        .catchToEffect()
                        .map { HomeCore.Action.fetchedAnime(keyPath: \.topTrendingAnime, result: $0) },
                    environment.animeClient.getTopUpcomingAnime()
                        .receive(on: environment.mainQueue)
                        .catchToEffect()
                        .map { HomeCore.Action.fetchedAnime(keyPath: \.topUpcomingAnime, result: $0) },
                    environment.animeClient.getTopAiringAnime()
                        .receive(on: environment.mainQueue)
                        .catchToEffect()
                        .map { HomeCore.Action.fetchedAnime(keyPath: \.topAiringAnime, result: $0) },
                    environment.animeClient.getHighestRatedAnime()
                        .receive(on: environment.mainQueue)
                        .catchToEffect()
                        .map { HomeCore.Action.fetchedAnime(keyPath: \.highestRatedAnime, result: $0) },
                    environment.animeClient.getMostPopularAnime()
                        .receive(on: environment.mainQueue)
                        .catchToEffect()
                        .map { HomeCore.Action.fetchedAnime(keyPath: \.mostPopularAnime, result: $0) },
                    environment.repositoryClient.observe(nil, [])
                        .receive(on: environment.mainQueue)
                        .eraseToEffect()
                        .map(Action.fetchedAnimesInDB)
                )
            case .fetchedAnime(let keyPath, .success(let anime)):
                state[keyPath: keyPath] = .success(.init(uniqueElements: anime))
            case .fetchedAnime(let keyPath, .failure(let error)):
                print(error)
                state[keyPath: keyPath] = .failed
            case .fetchedAnimesInDB(let animesInDB):
                var resumeWatchingAnimes = [EpisodeInfoWithAnimeId]()
                for animeInfo in animesInDB {
                    guard let recentEpisodeInfo = animeInfo.lastModifiedEpisode, !recentEpisodeInfo.finishedWatching else { continue }
                    resumeWatchingAnimes.append(.init(animeId: animeInfo.id, episodeInfo: recentEpisodeInfo))
                }

                return .init(value: .fetchResumeWatchingAnimes(resumeWatchingAnimes))

            case .fetchResumeWatchingAnimes(let episodeInfoWithAnimeIds):
                guard episodeInfoWithAnimeIds.count > 0 else {
                    state.resumeWatching = .success([])
                    break
                }

                return environment.animeClient.getAnimes(episodeInfoWithAnimeIds.map(\.animeId))
                    .receive(on: environment.mainQueue)
                    .catchToEffect()
                    .map {
                        $0.map { animes -> [EpisodeInfoWithAnime] in
                            var episodeInfosWithAnimes = [EpisodeInfoWithAnime]()

                            for anime in animes {
                                if let episodeInfo = episodeInfoWithAnimeIds.first(where: { $0.animeId == anime.id })?.episodeInfo {
                                    episodeInfosWithAnimes.append(.init(anime: anime, episodeInfo: episodeInfo))
                                }
                            }
                            return episodeInfosWithAnimes.sorted(by: \.episodeInfo.lastUpdatedProgress).reversed()
                        }
                    }
                    .map(Action.fetchedAnimeForResumeWatching)
            case .fetchedAnimeForResumeWatching(.success(let resumeWatchings)):
                state.resumeWatching = .success(.init(uniqueElements: resumeWatchings))
            case .fetchedAnimeForResumeWatching(.failure):
                state.resumeWatching = .failed

            case .resumeWatchingTapped:
                break
            case .binding:
                break
            case .animeTapped:
                break
            }
            return .none
        }
    )
        .binding()
}

extension HomeCore {
    struct EpisodeInfoWithAnimeId: Equatable {
        let animeId: Anime.ID
        let episodeInfo: EpisodeStore
    }

    struct EpisodeInfoWithAnime: Identifiable, Hashable {
        var id: Anime.ID { anime.id }
        let anime: Anime
        let episodeInfo: EpisodeStore
    }
}

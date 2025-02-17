//
//  DownloadsReducer.swift
//  Anime Now!
//
//  Created by ErrorErrorError on 9/25/22.
//  Copyright © 2022. All rights reserved.
//

import ComposableArchitecture
import DatabaseClient
import DownloaderClient
import SharedModels

// MARK: - DownloadsReducer

public struct DownloadsReducer: ReducerProtocol {
    public struct State: Equatable {
        var animes: [DownloaderClient.AnimeStorage] = []

        public init(
            animes: [DownloaderClient.AnimeStorage] = []
        ) {
            self.animes = animes
        }
    }

    public enum Action: Equatable {
        case onAppear
        case deleteEpisode(Anime.ID, Int)
        case cancelDownload(Anime.ID, Int)
        case playEpisode(DownloaderClient.AnimeStorage, [DownloaderClient.EpisodeStorage], Int)
        case onAnimes([DownloaderClient.AnimeStorage])
    }

    @Dependency(\.downloaderClient)
    var downloaderClient
    @Dependency(\.databaseClient)
    var databaseClient

    public init() {}

    public var body: some ReducerProtocol<State, Action> {
        Reduce(core)
    }
}

extension DownloadsReducer {
    func core(state: inout State, action: Action) -> EffectTask<Action> {
        switch action {
        case .onAppear:
            return .run { send in
                let list = downloaderClient.observe(nil)

                for await animes in list {
                    await send(.onAnimes(animes.sorted(by: \.title)))
                }
            }

        case let .onAnimes(animes):
            state.animes = animes

        case let .deleteEpisode(animeId, episodeNumber):
            return .run {
                await downloaderClient.delete(animeId, episodeNumber)
            }

        case let .cancelDownload(animeId, episodeNumber):
            return .run {
                await downloaderClient.cancel(animeId, episodeNumber)
            }

        case .playEpisode:
            break
        }

        return .none
    }
}

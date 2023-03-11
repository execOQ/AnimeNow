//
//  AppReducer.swift
//  Anime Now!
//
//  Created by ErrorErrorError on 9/4/22.
//  Copyright © 2022. All rights reserved.
//

import SwiftUI

import AnimeDetailFeature
import AnimePlayerFeature
import CollectionsFeature
import DownloadsFeature
import HomeFeature
import ModalOverlayFeature
import SearchFeature
import SettingsFeature

import DatabaseClient
import DiscordClient
import DownloaderClient
import VideoPlayerClient

import Logger
import SharedModels
import Utilities

import ComposableArchitecture

// MARK: - AppReducer

public struct AppReducer: ReducerProtocol {
    public init() {}

    public enum Route: String, CaseIterable {
        case home
        case search
        case collection
        case downloads
        case settings

        public var isIconSystemImage: Bool {
            switch self {
            case .collection:
                return false
            default:
                return true
            }
        }

        public var icon: String {
            switch self {
            case .home:
                return "house"
            case .search:
                return "magnifyingglass"
            case .downloads:
                return "arrow.down"
            case .collection:
                return "rectangle.stack.badge.play"
            case .settings:
                return "gearshape"
            }
        }

        public var selectedIcon: String {
            switch self {
            case .home:
                return "house.fill"
            case .search:
                return icon
            case .downloads:
                return icon
            case .collection:
                return "rectangle.stack.badge.play.fill"
            case .settings:
                return "gearshape.fill"
            }
        }

        public var title: String {
            .init(rawValue.prefix(1).capitalized + rawValue.dropFirst())
        }

        public static var allCases: [AppReducer.Route] {
            #if os(macOS)
            return [.home, .search, .collection, .downloads]
            #else
            return [.home, .search, .collection, .downloads, .settings]
            #endif
        }
    }

    public struct State: Equatable {
        @BindableState
        public var route = Route.home

        public var home = HomeReducer.State()
        public var collection = CollectionsReducer.State()
        public var search = SearchReducer.State()
        public var downloads = DownloadsReducer.State()
        public var settings = SettingsReducer.State()

        public var videoPlayer: AnimePlayerReducer.State?
        public var animeDetail: AnimeDetailReducer.State?
        public var modalOverlay: ModalOverlayReducer.State?

        public var totalDownloadsCount = 0

        public init() {}
    }

    public enum Action: BindableAction {
        case onAppear
        case setVideoPlayer(AnimePlayerReducer.State?)
        case setAnimeDetail(AnimeDetailReducer.State?)
        case setModalOverlay(ModalOverlayReducer.State?)
        case setDownloadingCount(Int)
        case appDelegate(AppDelegateReducer.Action)
        case home(HomeReducer.Action)
        case collection(CollectionsReducer.Action)
        case search(SearchReducer.Action)
        case downloads(DownloadsReducer.Action)
        case settings(SettingsReducer.Action)
        case videoPlayer(AnimePlayerReducer.Action)
        case animeDetail(AnimeDetailReducer.Action)
        case modalOverlay(ModalOverlayReducer.Action)
        case fetchedAnimeProviders(Loadable<[ProviderInfo]>)
        case binding(BindingAction<State>)
    }

    @Dependency(\.anilistClient)
    var anilistClient
    @Dependency(\.apiClient)
    var apiClient
    @Dependency(\.mainQueue)
    var mainQueue
    @Dependency(\.discordClient)
    var discordClient
    @Dependency(\.databaseClient)
    var databaseClient
    @Dependency(\.downloaderClient)
    var downloaderClient
    @Dependency(\.kitsuClient)
    var kitsuClient
    @Dependency(\.myanimelistClient)
    var myanimelistClient
    @Dependency(\.trackingListClient)
    var trackingListClient
    @Dependency(\.videoPlayerClient)
    var videoPlayerClient

    public var body: some ReducerProtocol<State, Action> {
        Scope(state: \.settings.userSettings, action: /Action.appDelegate) {
            AppDelegateReducer()
        }

        Scope(state: \.home, action: /Action.home) {
            HomeReducer()
        }

        Scope(state: \.search, action: /Action.search) {
            SearchReducer()
        }

        Scope(state: \.collection, action: /Action.collection) {
            CollectionsReducer()
        }

        Scope(state: \.downloads, action: /Action.downloads) {
            DownloadsReducer()
        }

        Scope(state: \.settings, action: /Action.settings) {
            SettingsReducer()
        }

        BindingReducer()

        Reduce(core)
            .ifLet(\.videoPlayer, action: /Action.videoPlayer) {
                AnimePlayerReducer()
            }
            .ifLet(\.animeDetail, action: /Action.animeDetail) {
                AnimeDetailReducer()
            }
            .ifLet(\.modalOverlay, action: /Action.modalOverlay) {
                ModalOverlayReducer()
            }

        Reduce(discordRichPresence)
    }
}

public extension AppReducer.State {
    var hasPendingChanges: Bool {
        videoPlayer != nil
    }
}

extension AppReducer {
    // swiftlint:disable cyclomatic_complexity function_body_length
    func core(state: inout State, action: Action) -> EffectTask<Action> {
        switch action {
        case .appDelegate(.appDidEnterBackground):
            if state.videoPlayer != nil {
                return .run { send in
                    await send(.videoPlayer(.saveState))
                }
            }

        case .appDelegate(.appWillTerminate):
            return .run { send in
                await send(.appDelegate(.appDidEnterBackground))
                #if os(macOS)
                // for macOS, save everything before fully closing app.
                try? await mainQueue.sleep(for: 0.5)
                await NSApp.reply(toApplicationShouldTerminate: true)
                #endif
            }

        case .appDelegate(.appDidFinishLaunching):
            state.settings.animeProviders = .loading
            return .run { send in
                await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        let downloadCounts = downloaderClient.count()

                        for await count in downloadCounts {
                            await send(.setDownloadingCount(count))
                        }
                    }

                    group.addTask {
                        await send(
                            .fetchedAnimeProviders(
                                .init { try await apiClient.request(.consumet(.listProviders(of: .ANIME))) }
                            )
                        )
                    }

                    group.addTask {
                        try await anilistClient.initialize()
                    }

                    group.addTask {
                        try await myanimelistClient.initialize()
                    }

                    group.addTask {
                        try await kitsuClient.initialize()
                    }
                }
            }

        case let .setVideoPlayer(item):
            state.videoPlayer = item

        case .videoPlayer(.onAppear):
            if state.settings.userSettings.trackingSettings.autoTrackEpisodes,
               let id = state.videoPlayer?.anime.id,
               let episodeProgress = state.videoPlayer?.stream.selectedEpisode {
                return .run {
                    try await trackingListClient.sync(id, max(episodeProgress - 1, 0))
                }
            }

        case let .setAnimeDetail(animeMaybe):
            if let anime = animeMaybe, state.animeDetail == nil {
                // Allow only replacing anime detail one at a time
                state.animeDetail = anime
            } else if animeMaybe == nil {
                state.animeDetail = nil
            }

        case let .home(.animeTapped(anime)),
             let .search(.onAnimeTapped(anime)):
            return .action(
                .setAnimeDetail(
                    .init(
                        anime: anime,
                        availableProviders: state.settings.selectableAnimeProviders
                    )
                ),
                animation: .interactiveSpring(response: 0.35, dampingFraction: 1.0)
            )

        case let .collection(.onAnimeTapped(animeId)):
            return .action(
                .setAnimeDetail(
                    .init(
                        animeId: animeId,
                        availableProviders: state.settings.selectableAnimeProviders
                    )
                ),
                animation: .interactiveSpring(response: 0.35, dampingFraction: 1.0)
            )

        case let .home(.anyAnimeTapped(animeId)):
            return .action(
                .setAnimeDetail(
                    .init(
                        animeId: animeId,
                        availableProviders: state.settings.selectableAnimeProviders
                    )
                ),
                animation: .interactiveSpring(response: 0.35, dampingFraction: 1.0)
            )

        case let .home(.watchEpisodeTapped(resumeWatching)):
            return .action(
                .setVideoPlayer(
                    .init(
                        player: videoPlayerClient.player(),
                        anime: resumeWatching.anime.eraseAsRepresentable(),
                        stream: .init(
                            animeId: resumeWatching.anime.id,
                            episodeId: resumeWatching.episode.number,
                            availableProviders: state.settings.selectableAnimeProviders
                        ),
                        enableDoubleTapGesture: state.settings.userSettings.videoSettings.doubleTapToSeek,
                        showSkipTimes: state.settings.userSettings.videoSettings.showTimeStamps,
                        skipInterval: state.settings.userSettings.videoSettings.skipTime,
                        autoTrackEpisodes: state.settings.userSettings.trackingSettings.autoTrackEpisodes
                    )
                )
            )

        case let .animeDetail(.play(anime, streamingProvider, selected)):
            return .action(
                .setVideoPlayer(
                    .init(
                        player: videoPlayerClient.player(),
                        anime: anime.eraseAsRepresentable(),
                        stream: .init(
                            animeId: anime.id,
                            episodeId: selected,
                            availableProviders: .init(
                                items: state.settings.animeProviders.value ?? [],
                                selected: streamingProvider.name
                            ),
                            streamingProviders: [streamingProvider]
                        ),
                        enableDoubleTapGesture: state.settings.userSettings.videoSettings.doubleTapToSeek,
                        showSkipTimes: state.settings.userSettings.videoSettings.showTimeStamps,
                        skipInterval: state.settings.userSettings.videoSettings.skipTime,
                        autoTrackEpisodes: state.settings.userSettings.trackingSettings.autoTrackEpisodes
                    )
                )
            )

        case let .downloads(.playEpisode(anime, episodes, selected)):
            return .action(
                .setVideoPlayer(
                    .init(
                        player: videoPlayerClient.player(),
                        anime: anime.eraseAsRepresentable(),
                        stream: .init(
                            animeId: anime.id,
                            episodeId: selected,
                            availableProviders: .init(
                                items: [.init(name: "Offline")],
                                selected: "Offline"
                            ),
                            streamingProviders: [.init(
                                name: "Offline",
                                episodes: episodes.map { episode in
                                    .init(
                                        title: episode.title,
                                        number: episode.number,
                                        description: "",
                                        isFiller: false,
                                        links: episode.links
                                    )
                                }
                            )]
                        ),
                        enableDoubleTapGesture: state.settings.userSettings.videoSettings.doubleTapToSeek,
                        showSkipTimes: state.settings.userSettings.videoSettings.showTimeStamps,
                        skipInterval: state.settings.userSettings.videoSettings.skipTime,
                        autoTrackEpisodes: state.settings.userSettings.trackingSettings.autoTrackEpisodes
                    )
                )
            )

        case .animeDetail(.close):
            return .action(
                .setAnimeDetail(nil),
                animation: .easeInOut(duration: 0.25)
            )

        case .videoPlayer(.close):
            return .action(
                .setVideoPlayer(nil)
            )

        case let .setModalOverlay(overlay):
            state.modalOverlay = overlay

        case let .setDownloadingCount(count):
            state.totalDownloadsCount = count

        case .collection(.onAddNewCollectionTapped):
            return .action(
                .setModalOverlay(
                    .addNewCollection(
                        .init()
                    )
                ),
                animation: .spring(response: 0.35, dampingFraction: 1)
            )

        case let .animeDetail(.downloadEpisode(episodeId)):
            guard let availableProviders = state.animeDetail?.stream.availableProviders,
                  let anime = state.animeDetail?.anime.value
            else {
                break
            }
            return .action(
                .setModalOverlay(
                    .downloadOptions(
                        .init(
                            anime: anime,
                            episodeId: episodeId,
                            availableProviders: availableProviders
                        )
                    )
                ),
                animation: .spring(response: 0.35, dampingFraction: 1)
            )

        case let .animeDetail(.showCollectionsList(animeId, collections)):
            return .action(
                .setModalOverlay(
                    .editCollection(
                        .init(
                            animeId: animeId,
                            collections: collections
                        )
                    )
                ),
                animation: .spring(response: 0.35, dampingFraction: 1)
            )

        case let .animeDetail(.fetchedCollectionStores(collections)):
            if case var .some(.editCollection(collectionState)) = state.modalOverlay {
                collectionState.collections = .init(collections)
                state.modalOverlay = .editCollection(collectionState)
            }

        case .modalOverlay(.downloadOptions(.downloadClicked)):
            if case let .downloadOptions(downloadState) = state.modalOverlay,
               let episode = downloadState.stream.episode?.eraseAsRepresentable(),
               let source = downloadState.stream.source {
                let downloadItem = DownloaderClient.Request(
                    anime: downloadState.anime,
                    episode: episode,
                    source: source
                )
                downloaderClient.download(downloadItem)

                return .action(.modalOverlay(.onClose))
            }

        case .modalOverlay(.addNewCollection(.saveTitle)):
            return .action(.modalOverlay(.onClose))

        case let .modalOverlay(.editCollection(.collectionSelectedToggle(collectionStoreId))):
            if var collection = state.animeDetail?.collectionStores.value?[id: collectionStoreId],
               let anime = state.animeDetail?.animeStore.value {
                if collection.animes[id: anime.id] != nil {
                    collection.animes[id: anime.id] = nil
                } else {
                    collection.animes[id: anime.id] = anime
                }

                return .run { [collection] in
                    try await databaseClient.insert(collection)
                }
            }

        case .modalOverlay(.onClose):
            return .action(.setModalOverlay(nil), animation: .spring(response: 0.35, dampingFraction: 1))

        case let .fetchedAnimeProviders(loadable):
            state.settings.animeProviders = loadable

            if loadable.failed {
                Logger.log(.error, "Failed to load anime providers.")
            }

        default:
            break
        }

        return .none
    }
}

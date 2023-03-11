//
//  AnimePlayerReducer.swift
//  Anime Now!
//
//  Created by ErrorErrorError on 10/1/22.
//  Copyright © 2022. All rights reserved.
//

import AnimeClient
import AnimeStreamLogic
import AVFoundation
import ComposableArchitecture
import DatabaseClient
import Foundation
import Logger
import SharedModels
import SwiftUI
import UserDefaultsClient
import Utilities
import VideoPlayerClient
import ViewComponents

// MARK: - AnimePlayerReducer

public struct AnimePlayerReducer: ReducerProtocol {
    typealias LoadableSourcesOptions = Loadable<SourcesOptions>

    public enum Sidebar: Hashable, CustomStringConvertible {
        case episodes
        case settings(SettingsState)
        case subtitles

        public var description: String {
            switch self {
            case .episodes:
                return "Episodes"
            case .settings:
                return "Settings"
            case .subtitles:
                return "Subtitles"
            }
        }

        public struct SettingsState: Hashable {
            public enum Section: Hashable, CustomStringConvertible {
                case provider
                case quality
                case audio
                case subtitleOptions

                public var description: String {
                    switch self {
                    case .provider:
                        return "Provider"
                    case .quality:
                        return "Quality"
                    case .audio:
                        return "Audio"
                    case .subtitleOptions:
                        return "Subtitle Options"
                    }
                }
            }

            var selectedSection: Section?
        }
    }

    public struct State: Equatable {
        public let player: AVPlayer
        public let anime: AnyAnimeRepresentable
        public var stream: AnimeStreamLogic.State

        public var animeStore = Loadable<AnimeStore>.idle
        public var skipTimes = Loadable<[SkipTime]>.idle

        public var selectedSidebar: Sidebar?
        public var showPlayerOverlay = true

        // Shared Player Properties

        public var playerProgress: Double = 0.0
        public var playerBuffered: Double { player.bufferProgress }
        public var playerDuration: Double { player.totalDuration }
        public var playerStatus = VideoPlayerClient.Status.idle
        public var playerIsFullScreen = false
        public var playerVolume: Double { player.isMuted ? 0.0 : Double(player.volume) }
        public var playerPiPStatus = VideoPlayer.PIPStatus.restoreUI
        @BindableState
        public var playerPiPActive = false
        @BindableState
        public var playerGravity = VideoPlayer.Gravity.resizeAspect

        public var enableDoubleTapGesture = true
        public var showSkipTimes = true
        public var skipInterval = 15
        public var autoTrackEpisodes = true

        // Internal

        var hasInitialized = false

        public init(
            player: AVPlayer,
            anime: AnyAnimeRepresentable,
            stream: AnimeStreamLogic.State,
            animeStore: Loadable<AnimeStore> = Loadable<AnimeStore>.idle,
            skipTimes: Loadable<[SkipTime]> = Loadable<[SkipTime]>.idle,
            selectedSidebar: AnimePlayerReducer.Sidebar? = nil,
            showPlayerOverlay: Bool = true,
            hasInitialized: Bool = false,
            playerProgress: Double = 0.0,
            playerStatus: VideoPlayerClient.Status = VideoPlayerClient.Status.idle,
            playerIsFullScreen: Bool = false,
            playerPiPStatus: VideoPlayer.PIPStatus = VideoPlayer.PIPStatus.restoreUI,
            playerPiPActive: Bool = false,
            playerGravity: AVLayerVideoGravity = VideoPlayer.Gravity.resizeAspect,
            enableDoubleTapGesture: Bool = true,
            showSkipTimes: Bool = true,
            skipInterval: Int = 15,
            autoTrackEpisodes: Bool = true
        ) {
            self.player = player
            self.anime = anime
            self.stream = stream
            self.animeStore = animeStore
            self.skipTimes = skipTimes
            self.selectedSidebar = selectedSidebar
            self.showPlayerOverlay = showPlayerOverlay
            self.hasInitialized = hasInitialized
            self.playerProgress = playerProgress
            self.playerStatus = playerStatus
            self.playerIsFullScreen = playerIsFullScreen
            self.playerPiPStatus = playerPiPStatus
            self.playerPiPActive = playerPiPActive
            self.playerGravity = playerGravity
            self.enableDoubleTapGesture = enableDoubleTapGesture
            self.showSkipTimes = showSkipTimes
            self.skipInterval = skipInterval
            self.autoTrackEpisodes = autoTrackEpisodes
        }
    }

    public enum Action: BindableAction {
        // View Actions

        case onAppear
        case playerTapped
        case closeButtonTapped

        case toggleEpisodes
        case toggleSettings
        case toggleSubtitles
        case selectSidebarSettings(Sidebar.SettingsState.Section?)
        case closeSidebar
        case saveState

        case stream(AnimeStreamLogic.Action)

        // MacOS Specific

        case isHoveringPlayer(Bool)
        case onMouseMoved

        // Internal Actions

        case showPlayerOverlay(Bool)
        case internalSetSidebar(Sidebar?)
        case closeSidebarAndShowControls
        case close

        case fetchedAnimeInfoStore([AnimeStore])
        case fetchSkipTimes
        case fetchedSkipTimes(Loadable<[SkipTime]>)

        // Sidebar Actions

        case sidebarSettingsSection(Sidebar.SettingsState.Section?)

        // Player Actions

        case togglePictureInPicture
        case play
        case pause
        case backwardsTapped
        case forwardsTapped
        case replayTapped
        case togglePlayback
        case startSeeking
        case stopSeeking
        case seeking(to: Double)
        case volume(to: Double)
        case toggleVideoGravity

        case playerStatus(VideoPlayerClient.Status)
        case playerProgress(Double)
        case playerPiPStatus(VideoPlayer.PIPStatus)
        case playerIsFullScreen(Bool)

        // Internal Video Player Actions

        case binding(BindingAction<State>)
    }

    @Dependency(\.mainQueue)
    var mainQueue
    @Dependency(\.mainRunLoop)
    var mainRunLoop
    @Dependency(\.animeClient)
    var animeClient
    @Dependency(\.databaseClient)
    var databaseClient
    @Dependency(\.trackingListClient)
    var trackingListClient
    @Dependency(\.videoPlayerClient)
    var videoPlayerClient
    @Dependency(\.userDefaultsClient)
    var userDefaultsClient

    public init() {}

    public var body: some ReducerProtocol<State, Action> {
        // Runs before changing video player state

        Reduce { state, action in
            let common: (inout State) -> EffectTask<Action> = { state in
                let copy = state
                state.playerProgress = .zero
                return self.saveEpisodeState(state: copy)
            }

            switch action {
            case .stream(.initialize):
                return .action(.fetchSkipTimes)

            case .stream(.selectEpisode):
                return .merge(
                    common(&state),
                    .action(.fetchSkipTimes),
                    .run {
                        await videoPlayerClient.execute(.clear)
                    }
                )

            case .stream(.selectProvider),
                 .stream(.selectLink),
                 .closeButtonTapped:
                return .merge(
                    common(&state),
                    .run {
                        await videoPlayerClient.execute(.clear)
                    }
                )

            case .stream(.selectSource):
                return common(&state)

            default:
                break
            }
            return .none
        }
        Scope(state: \.stream, action: /Action.stream) {
            AnimeStreamLogic()
        }
        BindingReducer()
        Reduce(self.core)
    }
}

// MARK: Status State

extension AnimePlayerReducer.State {
    enum Status: Equatable {
        case loading
        case playing
        case paused
        case replay
        case error(String)
    }

    var status: Status? {
        // Error States

        if stream.availableProviders.items.isEmpty {
            return .error("There are no available streaming providers at this time. Please try again later.")
            //        } else if case .none = stream.availableProviders.item {
            //            return .error("Please select a valid streaming provider.")
        } else if case .some(.failed) = stream.loadableStreamingProvider {
            return .error("There was an error retrieving episodes from selected streaming provider.")
        } else if case let .some(.success(item)) = stream.loadableStreamingProvider, item.episodes.isEmpty {
            return .error("There are no available episodes as of this time. Please try again later.")
        } else if case .failed = stream.sourceOptions {
            return .error("There was an error trying to retrieve sources. Please try again later.")
        } else if case let .success(sourcesOptions) = stream.sourceOptions, sourcesOptions.sources.isEmpty {
            return .error("There are currently no sources available for this episode. Please try again later.")
        } else if case .error = playerStatus {
            return .error("There was an error starting video player. Please try again later.")

            // Loading States

        } else if !(stream.loadableStreamingProvider?.finished ?? false) {
            return .loading
        } else if (episode?.links.count ?? 0) > 0 && !stream.sourceOptions.finished {
            return .loading
        } else if playerStatus == .finished || finishedWatching {
            return .replay
        } else if playerStatus == .idle || playerStatus == .loading || playerStatus == .playback(.buffering) {
            return .loading
        } else if playerStatus == .playback(.playing) {
            return .playing
        } else if playerStatus == .playback(.paused) {
            return .paused
        } else if case .loaded = playerStatus {
            return .paused
        }
        return nil
    }
}

// MARK: Episode Properties

extension AnimePlayerReducer.State {
    public var episode: AnyEpisodeRepresentable? {
        stream.episode?.eraseAsRepresentable()
    }

    var nextEpisode: Episode? {
        if let episode,
           let episodes = stream.streamingProvider?.episodes,
           let index = episodes.index(id: episode.id),
           (index + 1) < episodes.count {
            return episodes[index + 1]
        }
        return nil
    }
}

extension AnimePlayerReducer.State {
    var almostEnding: Bool {
        playerProgress >= 0.9
    }

    var finishedWatching: Bool {
        playerProgress >= 1.0
    }
}

extension AnimePlayerReducer.State {
    enum ActionType: Hashable {
        case skipRecap(to: Double)
        case skipOpening(to: Double)
        case skipEnding(to: Double)
        case nextEpisode(Episode.ID)

        var title: String {
            switch self {
            case .skipRecap:
                return "Skip Recap"
            case .skipOpening:
                return "Skip Opening"
            case .skipEnding:
                return "Skip Ending"
            case .nextEpisode:
                return "Next Episode"
            }
        }

        var image: String {
            switch self {
            case .nextEpisode:
                return "play.fill"
            default:
                return "forward.fill"
            }
        }

        var action: AnimePlayerReducer.Action {
            switch self {
            case let .nextEpisode(id):
                return .stream(.selectEpisode(id))
            case let .skipRecap(time), let .skipOpening(time), let .skipEnding(time):
                return .seeking(to: time)
            }
        }
    }

    var skipActions: [ActionType] {
        guard showSkipTimes else {
            return []
        }

        var actions = [ActionType]()

        actions.append(
            contentsOf: skipTimes.value?
                .filter { $0.isInRange(playerProgress) }
                .sorted(by: \.duration)
                .compactMap { skip in
                    switch skip.type {
                    case .recap:
                        return .skipRecap(to: skip.endTime)
                    case .opening, .mixedOpening:
                        return .skipOpening(to: skip.endTime)
                    case .ending, .mixedEnding:
                        return .skipEnding(to: skip.endTime)
                    }
                } ?? []
        )

        if let nextEpisode {
            let skipEnding = skipTimes.value?
                .filter { $0.type == .ending || $0.type == .mixedEnding }
                .min(by: \.startTime)
            if let skipEnding {
                if playerProgress >= skipEnding.startTime {
                    actions.append(.nextEpisode(nextEpisode.id))
                }
            } else if almostEnding {
                actions.append(.nextEpisode(nextEpisode.id))
            }
        }

        return actions
    }
}

extension AnimePlayerReducer {
    struct HidePlayerOverlayDelayCancellable: Hashable {}
    struct CancelAnimeStoreObservable: Hashable {}
    struct FetchSkipTimesCancellable: Hashable {}
    struct CancelAnimeFetchId: Hashable {}
    struct ObserveFullScreenNotificationId: Hashable {}
    struct VideoPlayerStatusCancellable: Hashable {}
    struct VideoPlayerProgressCancellable: Hashable {}

    // swiftlint:disable cyclomatic_complexity function_body_length
    func core(state: inout State, action: Action) -> EffectTask<Action> {
        switch action {
        // View Actions

        case .onAppear:
            let animeId = state.anime.id

            var effects = [EffectTask<Action>]()

            if !state.hasInitialized {
                state.hasInitialized = true

                effects.append(
                    .action(.stream(.initialize))
                )

                effects.append(
                    .run { send in
                        let animeStores: AsyncStream<[AnimeStore]> = databaseClient.observe(
                            AnimeStore.all
                                .where(\AnimeStore.id == animeId)
                                .limit(1)
                        )

                        for await animeStore in animeStores {
                            await send(.fetchedAnimeInfoStore(animeStore))
                        }
                    }
                    .cancellable(id: CancelAnimeStoreObservable.self)
                )

                #if os(macOS)
                effects.append(
                    .merge(
                        .run { send in
                            for await _ in await NotificationCenter.default.observeNotifications(
                                from: NSWindow.willEnterFullScreenNotification
                            ) {
                                await send(.playerIsFullScreen(true))
                            }
                        },
                        .run { send in
                            for await _ in await NotificationCenter.default.observeNotifications(
                                from: NSWindow.willExitFullScreenNotification
                            ) {
                                await send(.playerIsFullScreen(false))
                            }
                        }
                    )
                    .cancellable(id: ObserveFullScreenNotificationId.self)
                )
                #endif

                effects.append(
                    .run { send in
                        await withTaskCancellation(id: VideoPlayerStatusCancellable.self) {
                            for await status in videoPlayerClient.status() {
                                await send(.playerStatus(status))
                            }
                        }
                    }
                )

                effects.append(
                    .run { send in
                        await withTaskCancellation(id: VideoPlayerProgressCancellable.self) {
                            for await progress in videoPlayerClient.progress() {
                                await send(.playerProgress(progress))
                            }
                        }
                    }
                )
            }
            return .merge(effects)

        case .playerTapped:
            guard state.selectedSidebar == nil else {
                return .action(.closeSidebar)
            }

            guard !DeviceUtil.isMac else {
                break
            }

            let showingOverlay = !state.showPlayerOverlay

            var effects: [EffectTask<Action>] = [
                .action(.showPlayerOverlay(showingOverlay))
                    .animation(AnimePlayerReducer.overlayVisibilityAnimation)
            ]

            if showingOverlay, state.playerStatus == .playback(.playing) {
                // Show overlay with timeout if the video is currently playing
                effects.append(
                    hideOverlayAnimationDelay()
                )
            } else {
                effects.append(
                    cancelHideOverlayAnimationDelay()
                )
            }

            return .concatenate(effects)

        // MacOS specific
        case let .isHoveringPlayer(isHovering):
            if isHovering {
                // TODO: fix issue when trying to select router
                //                return .merge(
                //                    .run { send in
                //                        await send(
                //                            .showPlayerOverlay(true),
                //                            animation: AnimePlayerReducer.overlayVisibilityAnimation
                //                        )
                //                    },
                //                    hideOverlayAnimationDelay()
                //                )
            } else {
                return .merge(
                    .run { send in
                        await send(
                            .showPlayerOverlay(false),
                            animation: AnimePlayerReducer.overlayVisibilityAnimation
                        )
                    },
                    cancelHideOverlayAnimationDelay()
                )
            }

        case .onMouseMoved:
            var effects = [EffectTask<Action>]()

            if !state.showPlayerOverlay {
                effects.append(
                    .run { send in
                        await send(
                            .showPlayerOverlay(true),
                            animation: AnimePlayerReducer.overlayVisibilityAnimation
                        )
                    }
                )
            }

            effects.append(
                hideOverlayAnimationDelay()
            )

            return .merge(effects)

        case .toggleEpisodes:
            if case .episodes = state.selectedSidebar {
                return .action(
                    .internalSetSidebar(nil),
                    animation: .easeInOut(duration: 0.35)
                )
            } else {
                return .action(
                    .internalSetSidebar(.episodes),
                    animation: .easeInOut(duration: 0.35)
                )
            }

        case .toggleSettings:
            if case .settings = state.selectedSidebar {
                return .action(
                    .internalSetSidebar(nil),
                    animation: .easeInOut(duration: 0.35)
                )
            } else {
                return .action(
                    .internalSetSidebar(.settings(.init())),
                    animation: .easeInOut(duration: 0.35)
                )
            }

        case .toggleSubtitles:
            if case .subtitles = state.selectedSidebar {
                return .action(
                    .internalSetSidebar(nil),
                    animation: .easeInOut(duration: 0.35)
                )
            } else {
                return .action(
                    .internalSetSidebar(.subtitles),
                    animation: .easeInOut(duration: 0.35)
                )
            }

        case .closeButtonTapped:
            return .merge(
                .cancel(id: VideoPlayerStatusCancellable.self),
                .cancel(id: VideoPlayerProgressCancellable.self),
                .cancel(id: ObserveFullScreenNotificationId.self),
                .cancel(id: HidePlayerOverlayDelayCancellable.self),
                .cancel(id: CancelAnimeStoreObservable.self),
                .cancel(id: CancelAnimeFetchId.self),
                .cancel(id: FetchSkipTimesCancellable.self),
                .action(.close)
            )

        case .closeSidebar:
            return .action(
                .internalSetSidebar(nil),
                animation: .easeInOut(duration: 0.25)
            )

        case let .selectSidebarSettings(section):
            return .action(.sidebarSettingsSection(section))
                .animation(.easeInOut(duration: 0.25))

        case let .showPlayerOverlay(show):
            state.showPlayerOverlay = show

        // Internal Actions

        case .closeSidebarAndShowControls:
            state.selectedSidebar = nil
            return .action(.showPlayerOverlay(true))

        case let .internalSetSidebar(route):
            state.selectedSidebar = route

            if route != nil {
                return .merge(
                    cancelHideOverlayAnimationDelay(),
                    .action(.showPlayerOverlay(false))
                )
            }

        case .close:
            break

        // Section actions

        case let .sidebarSettingsSection(section):
            if case .settings = state.selectedSidebar {
                state.selectedSidebar = .settings(.init(selectedSection: section))
            }

        // Fetched Anime Store

        case let .fetchedAnimeInfoStore(animeStores):
            state.animeStore = .success(.findOrCreate(state.anime, animeStores))

        // Fetch Skip Times

        case .fetchSkipTimes:
            guard let episode = state.episode, let malId = state.anime.malId else {
                return .action(.fetchedSkipTimes(.success([])))
            }

            state.skipTimes = .loading

            let episodeNumber = episode.number
            return .run { [malId, episodeNumber] in
                await .fetchedSkipTimes(
                    .init { try await animeClient.getSkipTimes(malId, episodeNumber) }
                )
            }
            .cancellable(id: FetchSkipTimesCancellable.self, cancelInFlight: true)

        case let .fetchedSkipTimes(loadable):
            state.skipTimes = loadable

        // Video Player Actions

        case .play:
            return .run {
                await videoPlayerClient.execute(.resume)
            }

        case .pause:
            return .run {
                await videoPlayerClient.execute(.pause)
            }

        case .togglePictureInPicture:
            state.playerPiPActive.toggle()

        case .backwardsTapped:
            guard state.playerDuration > 0.0 else {
                break
            }
            let progress = state.playerProgress - Double(state.skipInterval) / state.playerDuration
            let requestedTime = max(progress, .zero)
            state.playerProgress = requestedTime
            return .run {
                await videoPlayerClient.execute(.seekTo(requestedTime))
            }

        case .forwardsTapped:
            guard state.playerDuration > 0.0 else {
                break
            }
            let progress = state.playerProgress + Double(state.skipInterval) / state.playerDuration
            let requestedTime = min(progress, 1.0)
            state.playerProgress = requestedTime
            return .run {
                await videoPlayerClient.execute(.seekTo(requestedTime))
            }

        case .toggleVideoGravity:
            switch state.playerGravity {
            case .resizeAspect:
                state.playerGravity = .resizeAspectFill

            default:
                state.playerGravity = .resizeAspect
            }
            return hideOverlayAnimationDelay()

        // Internal Video Player

        case .replayTapped:
            state.playerProgress = 0
            return .run { _ in
                await videoPlayerClient.execute(.seekTo(0))
                await videoPlayerClient.execute(.resume)
            }

        case .togglePlayback:
            if case .playing = state.status {
                return .run {
                    await videoPlayerClient.execute(.pause)
                }
            } else {
                return .run {
                    await videoPlayerClient.execute(.resume)
                }
            }

        case .startSeeking:
            return .run {
                await videoPlayerClient.execute(.pause)
            }

        case let .seeking(to: to):
            let clamped = min(1.0, max(0.0, to))
            state.playerProgress = clamped
            return .run {
                await videoPlayerClient.execute(.seekTo(clamped))
            }

        case .stopSeeking:
            return .run { _ in
                await videoPlayerClient.execute(.resume)
            }

        case let .volume(to: volume):
            let clamped = min(1.0, max(0.0, volume))

            return .merge(
                .run {
                    await videoPlayerClient.execute(.volume(clamped))
                },
                hideOverlayAnimationDelay()
            )

        // Player Actions Observer

        case .playerStatus(.finished):
            state.playerStatus = .finished
            return saveEpisodeState(state: state)

        case let .playerStatus(.loaded(duration)):
            state.playerStatus = .loaded(duration: duration)

            // First time duration is set and is not zero, resume progress
            if let animeInfo = state.animeStore.value,
               let episode = state.episode,
               let savedEpisodeProgress = animeInfo.episodes.first(where: { $0.number == episode.number }),
               !savedEpisodeProgress.almostFinished {
                state.playerProgress = savedEpisodeProgress.progress ?? .zero
                return .run { _ in
                    await videoPlayerClient.execute(.seekTo(savedEpisodeProgress.progress ?? .zero))
                    await videoPlayerClient.execute(.resume)
                }
            } else {
                state.playerProgress = .zero
                return .run { _ in
                    await videoPlayerClient.execute(.seekTo(.zero))
                    await videoPlayerClient.execute(.resume)
                }
            }

        case let .playerStatus(status):
            state.playerStatus = status

            guard !DeviceUtil.isMac else {
                break
            }

            if case .playback(.playing) = status, state.showPlayerOverlay {
                return hideOverlayAnimationDelay()
            } else if state.showPlayerOverlay {
                return cancelHideOverlayAnimationDelay()
            }

        case let .playerProgress(progress):
            state.playerProgress = progress

        case let .playerPiPStatus(status):
            state.playerPiPStatus = status

            if status == .willStop {
                return saveEpisodeState(state: state)
            }

        case let .playerIsFullScreen(fullscreen):
            state.playerIsFullScreen = fullscreen

        case .saveState:
            return saveEpisodeState(state: state)

        case .stream(.selectSource), .stream(.fetchedSources(.success)):
            if let source = state.stream.source {
                let anime = state.anime
                let episode = state.episode
                let episodeNumber = state.stream.selectedEpisode
                return .run {
                    await videoPlayerClient.execute(
                        .play(
                            .init(
                                source: source,
                                metadata: .init(
                                    videoTitle: episode?.title ?? "Episode \(episodeNumber)",
                                    videoAuthor: anime.title,
                                    thumbnail: (episode?.thumbnail ?? anime.posterImage.largest)?.link
                                )
                            )
                        )
                    )
                }
            }

        case .binding:
            break

        case .stream:
            break
        }

        return .none
    }
}

extension AnimePlayerReducer {
    static let overlayVisibilityAnimation = Animation.easeInOut(
        duration: 0.3
    )

    // Internal Effects

    private func hideOverlayAnimationDelay() -> EffectTask<Action> {
        .run { send in
            try await withTaskCancellation(id: HidePlayerOverlayDelayCancellable.self, cancelInFlight: true) {
                try await self.mainQueue.sleep(for: .seconds(2.5))
                await send(
                    .showPlayerOverlay(false),
                    animation: AnimePlayerReducer.overlayVisibilityAnimation
                )
            }
        }
    }

    private func cancelHideOverlayAnimationDelay() -> EffectTask<Action> {
        .cancel(id: HidePlayerOverlayDelayCancellable.self)
    }

    private func saveEpisodeState(state: State, episodeId: Episode.ID? = nil) -> EffectTask<Action> {
        struct SyncCancellationId: Hashable {}

        let episodeId = episodeId ?? state.stream.selectedEpisode
        guard let episode = state.stream.streamingProvider?.episodes[id: episodeId],
              state.playerDuration > 0,
              var animeStore = state.animeStore.value
        else {
            return .none
        }

        let progress = state.playerProgress

        animeStore.updateProgress(
            for: episode,
            progress: progress
        )

        let autoTrack = state.autoTrackEpisodes

        return .merge(
            .run { [animeStore] _ in
                try await databaseClient.insert(animeStore)
            },
            .run { [animeStore, episodeId] _ in
                if autoTrack,
                   let episode = animeStore.episodes.first(where: { $0.number == episodeId }),
                   episode.almostFinished {
                    try await withTaskCancellation(id: SyncCancellationId.self, cancelInFlight: true) {
                        try await trackingListClient.sync(animeStore.id, episodeId)
                    }
                }
            }
        )
    }
}

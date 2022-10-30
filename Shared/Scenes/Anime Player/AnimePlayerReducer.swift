//
//  AnimePlayerReducer.swift
//  Anime Now!
//
//  Created by ErrorErrorError on 10/1/22.
//  Copyright © 2022. All rights reserved.
//

import Foundation
import ComposableArchitecture
import AVFoundation
import SwiftUI

struct AnimePlayerReducer: ReducerProtocol {
    typealias LoadableEpisodes = Loadable<[AnyEpisodeRepresentable]>
    typealias LoadableSourcesOptions = Loadable<SourcesOptions>

    enum Sidebar: Hashable, CustomStringConvertible {
        case episodes
        case settings(SettingsState)
        case subtitles

        var description: String {
            switch self {
            case .episodes:
                return "Episodes"
            case .settings:
                return "Settings"
            case .subtitles:
                return "Subtitles"
            }
        }

        struct SettingsState: Hashable {
            enum Section: Hashable {
                case provider
                case quality
                case audio
            }

            var selectedSection: Section?
        }
    }

    struct State: Equatable {
        let anime: AnyAnimeRepresentable

        var episodes = LoadableEpisodes.idle
        var sourcesOptions = LoadableSourcesOptions.idle
        var animeStore = Loadable<AnimeStore>.idle
        var skipTimes = Loadable<[SkipTime]>.idle

        var selectedEpisode: Episode.ID
        var selectedProvider: Provider.ID?
        var selectedSource: Source.ID?
        var selectedSidebar: Sidebar?
        var selectedSubtitle: Source.Subtitle.ID?

        var showPlayerOverlay = true

        // Internal

        var hasInitialized = false

        // Shared Player Properties

        @BindableState var playerAction: VideoPlayer.Action? = nil
        var playerProgress = Double.zero
        var playerBuffered = Double.zero
        var playerDuration = Double.zero
        var playerStatus = VideoPlayer.Status.idle
        var playerPiPStatus = VideoPlayer.PIPStatus.restoreUI

        // MacOS Properties

        var playerVolume = 0.0

        init(
            anime: AnyAnimeRepresentable,
            episodes: [AnyEpisodeRepresentable]? = nil,
            selectedEpisode: Episode.ID
        ) {
            self.anime = anime
            if let episodes = episodes {
                self.episodes = .success(episodes)
            } else {
                self.episodes = .idle
            }
            self.selectedEpisode = selectedEpisode
        }
    }

    enum Action: Equatable, BindableAction {

        // View Actions

        case onAppear
        case playerTapped
        case closeButtonTapped

        case showEpisodesSidebar
        case showSettingsSidebar
        case showSubtitlesSidebar
        case selectSidebarSettings(Sidebar.SettingsState.Section?)
        case closeSidebar

        case selectEpisode(AnyEpisodeRepresentable.ID, saveProgress: Bool = true)
        case selectProvider(Provider.ID)
        case selectSource(Source.ID?)
        case selectSubtitle(Source.Subtitle.ID?)
        case selectAudio(Provider.ID)

        // MacOS Specific
        case isHoveringPlayer(Bool)
        case onMouseMoved

        // Internal Actions
        case showPlayerOverlay(Bool)
        case internalSetSidebar(Sidebar?)
        case internalSetSource(Source.ID?)
        case saveEpisodeProgress(AnyEpisodeRepresentable.ID?)
        case closeSidebarAndShowControls
        case close

        case fetchedAnimeInfoStore([AnimeStore])
        case fetchedEpisodes(TaskResult<[Episode]>)
        case fetchSourcesOptions
        case fetchedSourcesOptions(TaskResult<SourcesOptions>)
        case fetchSkipTimes
        case fetchedSkipTimes(TaskResult<[SkipTime]>)

        // Sidebar Actions

        case sidebarSettingsSection(Sidebar.SettingsState.Section?)

        // Player Actions

        case togglePictureInPicture
        case play
        case backwardsTapped
        case forwardsTapped
        case replayTapped
        case togglePlayback
        case startSeeking
        case stopSeeking
        case seeking(to: Double)
        case volume(to: Double)

        case playerStatus(VideoPlayer.Status)
        case playerAction(VideoPlayer.Action)
        case playerProgress(Double)
        case playerDuration(Double)
        case playerBuffer(Double)
        case playerPiPStatus(VideoPlayer.PIPStatus)
        case playerPlayedToEnd
        case playerVolume(Double)

        // Internal Video Player Actions

        case binding(BindingAction<State>)
    }

    @Dependency(\.animeClient) var animeClient
    @Dependency(\.mainQueue) var mainQueue
    @Dependency(\.mainRunLoop) var mainRunLoop
    @Dependency(\.repositoryClient) var repositoryClient
    @Dependency(\.userDefaultsClient) var userDefaultsClient
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
        if case .failed = episodes {
            return .error("There was an error retrieving episodes at this time. Please try again later.")
        } else if case .success(let episodes) = episodes, episodes.count == 0 {
            return .error("There are no available episodes as of this time. Please try again later.")
        } else if let episode = episode, episode.providers.count == 0 {
            return .error("There are no providers available for this episode. Please try again later.")
        } else if case .failed = sourcesOptions {
            return .error("There was an error trying to retrieve sources. Please try again later.")
        } else if case .success(let sourcesOptions) = sourcesOptions, sourcesOptions.sources.count == 0 {
            return .error("There are currently no sources available for this episode. Please try again later.")
        } else if case .error = playerStatus {
            return .error("There was an error starting video player. Please try again later.")

        // Loading States
        } else if !episodes.finished {
            return .loading
        } else if (episode?.providers.count ?? 0) > 0 && !sourcesOptions.finished {
            return .loading
        } else if finishedWatching {
            return .replay
        } else if playerStatus == .idle || playerStatus == .loading || playerStatus == .buffering {
            return .loading
        } else if playerStatus == .playing {
            return .playing
        } else if playerStatus == .paused || playerStatus == .readyToPlay {
            return .paused
        }
        return nil
    }
}

// MARK: Episode Properties

extension AnimePlayerReducer.State {
    var episode: AnyEpisodeRepresentable? {
        if let episodes = episodes.value {
            return episodes[id: selectedEpisode]
        }

        return nil
    }

    fileprivate var provider: Provider? {
        if let episode = episode, let selectedProvider = selectedProvider {
            return episode.providers.first(where: { $0.id == selectedProvider })
        }

        return nil
    }

    var source: Source? {
        if let sourceId = selectedSource, let sources = sourcesOptions.value?.sources {
            return sources[id: sourceId]
        }
        return nil
    }

    var nextEpisode: AnyEpisodeRepresentable? {
        if let episode = episode,
           let episodes = episodes.value,
           let index = episodes.index(id: episode.id),
           (index + 1) < episodes.count {
            return episodes[index + 1]
        }
        return nil
    }

    var subtitle: Source.Subtitle? {
        if let subtitleId = selectedSubtitle, let subtitles = sourcesOptions.value?.subtitles {
            return subtitles[id: subtitleId]
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
    enum ActionType: Equatable {
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
    }

    var skipAction: ActionType? {
        if let skipTime = skipTimes.value?.first(where: { $0.isInRange(playerProgress) }) {
            switch skipTime.type {
            case .recap:
                return .skipRecap(to: skipTime.endTime)
            case .opening, .mixedOpening:
                return .skipOpening(to: skipTime.endTime)
            case .ending, .mixedEnding:
                return .skipEnding(to: skipTime.endTime)
            }
        } else if almostEnding, let nextEpisode = nextEpisode {
            return .nextEpisode(nextEpisode.id)
        }
        return nil
    }
}

extension AnimePlayerReducer {
    struct HidePlayerOverlayDelayCancellable: Hashable {}
    struct FetchEpisodesCancellable: Hashable {}
    struct FetchSourcesCancellable: Hashable {}
    struct CancelAnimeStoreObservable: Hashable {}
    struct FetchSkipTimesCancellable: Hashable {}
    struct CancelAnimeFetchId: Hashable {}

    @ReducerBuilder<State, Action>
    var body: Reduce<State, Action> {
        BindingReducer()
        Reduce(self.core)
    }

    func core(state: inout State, action: Action) -> EffectTask<Action> {
        switch action {

        // View Actions

        case .onAppear:
            let animeId = state.anime.id

            var effects = [EffectTask<Action>]()

            if !state.hasInitialized {
                state.hasInitialized = true
                effects.append(
                    .run { send in
                        let animeStores: AsyncStream<[AnimeStore]> = repositoryClient.observe(
                            .init(
                                format: "id == %d",
                                animeId
                            )
                        )

                        for await animeStore in animeStores {
                            await send(.fetchedAnimeInfoStore(animeStore))
                        }
                    }
                    .cancellable(id: CancelAnimeStoreObservable())
                )

                if !state.episodes.hasInitialized {
                    state.episodes = .loading

                    effects.append(
                        .run { send in
                            await send(
                                .fetchedEpisodes(
                                    .init {
                                        try await animeClient.getEpisodes(animeId)
                                    }
                                )
                            )
                        }
                        .cancellable(id: FetchEpisodesCancellable())
                    )
                } else if state.episode != nil {
                    effects.append(
                        .action(.selectEpisode(state.selectedEpisode, saveProgress: false))
                    )
                }
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

            if showingOverlay && state.playerStatus == .playing {
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
        case .isHoveringPlayer(let isHovering):
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

        case .showEpisodesSidebar:
            return .action(
                .internalSetSidebar(.episodes),
                animation: .easeInOut(duration: 0.35)
            )

        case .showSettingsSidebar:
            return .action(
                .internalSetSidebar(.settings(.init())),
                animation: .easeInOut(duration: 0.35)
            )

        case .showSubtitlesSidebar:
            return .action(
                .internalSetSidebar(.subtitles),
                animation: .easeInOut(duration: 0.35)
            )

        case .closeButtonTapped:
            let selectedEpisodeId = state.selectedEpisode
            return .concatenate(
                .action(.saveEpisodeProgress(selectedEpisodeId)),
                .cancel(id: HidePlayerOverlayDelayCancellable()),
                .cancel(id: CancelAnimeStoreObservable()),
                .cancel(id: CancelAnimeFetchId()),
                .cancel(id: FetchSourcesCancellable()),
                .cancel(id: FetchEpisodesCancellable()),
                .cancel(id: FetchSkipTimesCancellable()),
                .run {
                    try await mainQueue.sleep(for: 0.25)
                    await $0(.close)
                }
            )

        case .closeSidebar:
            return .action(
                .internalSetSidebar(nil),
                animation: .easeInOut(duration: 0.25)
            )

        case .selectEpisode(let episodeId, let saveProgress):
            var effects = [Effect<Action, Never>]()

            // Before selecting episode, save progress

            if saveProgress {
                let episodeId = state.selectedEpisode
                effects.append(.action(.saveEpisodeProgress(episodeId)))
            }

            state.selectedEpisode = episodeId

            let lastSelectedProvider: String? = userDefaultsClient.dataForKey(.videoPlayerProvider)?.toObject()
            let lastSelectedIsDub: Bool? = userDefaultsClient.boolForKey(.videoPlayerAudioIsDub)

            var providerId = state.episode?.providers.first(
                where: { $0.description == lastSelectedProvider && $0.dub == lastSelectedIsDub }
            )?.id

            providerId = providerId ?? state.episode?.providers.first(
                where: { $0.dub == lastSelectedIsDub }
            )?.id

            providerId = providerId ?? state.episode?.providers.first(
                where: { $0.description == lastSelectedProvider }
            )?.id

            providerId = providerId ?? state.episode?.providers.first?.id

            effects.append(self.internalSetProvider(providerId, state: &state))
            effects.append(.action(.fetchSkipTimes))

            return .concatenate(effects)

        case .selectProvider(let providerId):
            guard let providerName = state.episode?.providers[id: providerId]?.description else { break }
            guard providerName != state.provider?.description else { break }

            let lastSelectedIsDub: Bool? = userDefaultsClient.boolForKey(.videoPlayerAudioIsDub)

            var providerId = state.episode?.providers.first(where: { $0.description == providerName && $0.dub == lastSelectedIsDub })?.id
            providerId = providerId ?? state.episode?.providers.first(where: { $0.description == providerName })?.id

            guard let providerId = providerId else { break }

            return .concatenate(
                .action(.saveEpisodeProgress(state.selectedEpisode)),
                self.internalSetProvider(providerId, state: &state)
            )

        case .selectSource(let sourceId):
            let selectedEpisode = state.selectedEpisode
            return .concatenate(
                .action(.saveEpisodeProgress(selectedEpisode)),
                .action(.internalSetSource(sourceId))
            )

        case .selectSubtitle(let subtitleId):
            state.selectedSubtitle = subtitleId

            let subtitleData = state.subtitle?.lang.toData()
            return .run {
                await userDefaultsClient.setData(.videoPlayerSubtitle, subtitleData ?? .empty)
            }

        case .selectSidebarSettings(let section):
            return .action(.sidebarSettingsSection(section))
                .animation(.easeInOut(duration: 0.25))

        case .selectAudio(let providerId):
            guard providerId != state.provider?.id else { break }
            guard let provider = state.episode?.providers[id: providerId] else { break }

            return .concatenate(
                .run {
                    await userDefaultsClient.setBool(.videoPlayerAudioIsDub, provider.dub ?? false)
                },
                .action(.saveEpisodeProgress(state.selectedEpisode)),
                self.internalSetProvider(providerId, state: &state)
            )

        case .showPlayerOverlay(let show):
            state.showPlayerOverlay = show

        // Internal Actions

        case .saveEpisodeProgress(let episodeId):
            guard let episodeId = episodeId, let episode = state.episodes.value?[id: episodeId] else { break }
            guard state.playerDuration > 0 else { break }
            guard var animeStore = state.animeStore.value else { break }

            let progress = state.playerProgress

            animeStore.updateProgress(
                for: episode,
                anime: state.anime,
                progress: progress
            )

            return .fireAndForget { [animeStore] in
                _ = try await repositoryClient.insertOrUpdate(animeStore)
            }

        case .closeSidebarAndShowControls:
            state.selectedSidebar = nil
            return .action(.showPlayerOverlay(true))

        case .internalSetSource(let source):
            state.selectedSource = source
            if let qualityData = state.source?.quality.toData() {
                return .run {
                    await userDefaultsClient.setData(.videoPlayerQuality, qualityData)
                }
            }

        case .internalSetSidebar(let route):
            state.selectedSidebar = route

            if route != nil {
                return .merge(
                    self.cancelHideOverlayAnimationDelay(),
                    .action(.showPlayerOverlay(false))
                )
            }

        case .close:
            break

        // Section actions

        case .sidebarSettingsSection(let section):
            if case .settings = state.selectedSidebar {
                state.selectedSidebar = .settings(.init(selectedSection: section))
            }

        // Fetched Anime Store

        case .fetchedAnimeInfoStore(let animeStores):
            state.animeStore = .success(.findOrCreate(state.anime, animeStores))

        case .fetchedEpisodes(.success(let episodes)):
            state.episodes = .success(episodes.map({ $0.asRepresentable() }))
            let selectedEpisodeId = state.selectedEpisode
            return .action(.selectEpisode(selectedEpisodeId, saveProgress: false))

        case .fetchedEpisodes(.failure):
            state.episodes = .failed

        // Fetch SourcesOptions

        case .fetchSourcesOptions:
            guard let provider = state.provider else { break }

            state.sourcesOptions = .loading

            return .run {
                await .fetchedSourcesOptions(
                    .init { try await animeClient.getSources(provider) }
                )
            }
            .cancellable(id: FetchSourcesCancellable(), cancelInFlight: true)

        case .fetchedSourcesOptions(.success(let sources)):
            state.sourcesOptions = .success(sources)

            let lastSelectedQuality: Source.Quality? = userDefaultsClient.dataForKey(.videoPlayerQuality)?.toObject()
            let lastSelectedSubtitles: String? = userDefaultsClient.dataForKey(.videoPlayerSubtitle)?.toObject()

            let sourceId = sources.sources.first(where: { $0.quality == lastSelectedQuality })?.id ?? sources.sources.first?.id
            let subtitleId = sources.subtitles.first(where: { $0.lang == lastSelectedSubtitles })?.id ?? nil

            state.selectedSubtitle = subtitleId
            state.selectedSource = sourceId

        case .fetchedSourcesOptions(.failure):
            state.sourcesOptions = .failed
            state.selectedSource = nil

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
            .cancellable(id: FetchSkipTimesCancellable(), cancelInFlight: true)

        case .fetchedSkipTimes(.success(let skipTimes)):
            state.skipTimes = .success(skipTimes)

        case .fetchedSkipTimes(.failure):
            state.skipTimes = .success([])

        // Video Player Actions

        case .play:
            state.playerAction = .play

        case .togglePictureInPicture:
            if state.playerPiPStatus == .didStart {
                state.playerAction = .pictureInPicture(enable: false)
            } else {
                state.playerAction = .pictureInPicture(enable: true)
            }

        case .backwardsTapped:
            guard state.playerDuration > 0.0 else { break }
            let progress = state.playerProgress - 15 / state.playerDuration

            let requestedTime = max(progress, .zero)
            state.playerAction = .seekTo(requestedTime)
            state.playerProgress = requestedTime

        case .forwardsTapped:
            guard state.playerDuration > 0.0 else { break }
            let progress = state.playerProgress + 15 / state.playerDuration

            let requestedTime = min(progress, 1.0)
            state.playerAction = .seekTo(requestedTime)
            state.playerProgress = requestedTime

        // Internal Video Player 
        case .replayTapped:
            state.playerAction = .seekTo(0)
            return .run { send in
                try? await mainQueue.sleep(for: 0.5)
                await send(.play)
            }

        case .togglePlayback:
            if case .playing = state.status {
                state.playerAction = .pause
            } else {
                state.playerAction = .play
            }

        case .startSeeking:
            state.playerAction = .pause

        case .stopSeeking:
            state.playerAction = .seekTo(state.playerProgress)
            return .run { send in
                try? await mainQueue.sleep(for: 0.5)
                await send(.play)
            }

        case .seeking(to: let to):
            state.playerProgress = to

        case .volume(to: let volume):
            struct PlayerVolumeDebounceId: Hashable {}

            state.playerVolume = volume
            return .action(.playerAction(.volume(state.playerVolume)))
                .debounce(id: PlayerVolumeDebounceId(), for: 0.5, scheduler: mainQueue)

        // Player Actions Observer

        case .playerAction(let action):
            state.playerAction = action

        case .playerStatus(let status):
            guard status != state.playerStatus else { break }
            state.playerStatus = status

            guard !DeviceUtil.isMac else { break }

            if case .playing = status, state.showPlayerOverlay {
                return hideOverlayAnimationDelay()
            } else if state.showPlayerOverlay {
                return cancelHideOverlayAnimationDelay()
            }

        case .playerProgress(let progress):
            guard progress != state.playerProgress else { break }
            state.playerProgress = progress

        case .playerDuration(let duration):

            // First time duration is set and is not zero, resume progress

            if duration != .zero {
                if let animeInfo = state.animeStore.value,
                   let episode = state.episode,
                   let savedEpisodeProgress = animeInfo.episodeStores.first(where: { $0.number ==  episode.number }),
                   !savedEpisodeProgress.almostFinished {
                    state.playerProgress = savedEpisodeProgress.progress
                    state.playerAction = .seekTo(savedEpisodeProgress.progress)
                } else {
                    state.playerProgress = 0
                    state.playerAction = .seekTo(.zero)
                }
            }

            state.playerDuration = duration

        case .playerBuffer(let buffer):
            state.playerBuffered = buffer

        case .playerPiPStatus(let status):
            state.playerPiPStatus = status

        case .playerPlayedToEnd:
            // TODO: Check if autoplay is set
            return .action(.saveEpisodeProgress(state.selectedEpisode))

        case .playerVolume(let volume):
            state.playerVolume = volume

        case .binding:
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
        struct HideOverlayAnimationDebounceID: Hashable {}

        return .run { send in
            try await withTaskCancellation(id: HideOverlayAnimationDebounceID(), cancelInFlight: true) {
                try await self.mainQueue.sleep(for: .seconds(2.5))
                await send(
                    .showPlayerOverlay(false),
                    animation: AnimePlayerReducer.overlayVisibilityAnimation
                )
            }
        }
    }

    private func cancelHideOverlayAnimationDelay() -> EffectTask<Action> {
        .cancel(id: HidePlayerOverlayDelayCancellable())
    }

    private func internalSetProvider(_ providerId: Provider.ID?, state: inout State) -> EffectTask<Action> {
        // Before selecting provider, save progress

        state.selectedProvider = providerId

        let providerData = state.provider?.description.toData()

        return .concatenate(
            .run { send in
                if let providerData = providerData {
                    await userDefaultsClient.setData(.videoPlayerProvider, providerData)
                }

                await send(.fetchSourcesOptions)
            }
        )
    }
}

//
//  AnimePlayerView+macOS.swift
//  Anime Now! (macOS)
//
//  Created by ErrorErrorError on 10/16/22.
//

#if os(macOS)
import AppKit
import ComposableArchitecture
import SharedModels
import SwiftUI
import ViewComponents

extension AnimePlayerView {
    @ViewBuilder
    var playerControlsOverlay: some View {
        WithViewStore(store) { state in
            state.canShowPlayerOverlay
        } content: { viewState in
            GeometryReader { _ in
                VStack(spacing: 0) {
                    if viewState.state {
                        topPlayerItems
                            .padding(.horizontal, 24)
                    }
                    Spacer()
                    episodesOverlay
                    skipButton
                        .padding(.horizontal, 24)
                    if viewState.state {
                        bottomPlayerItems
                            .padding(.horizontal, 24)
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
                .padding(.vertical, 24)
                .background(
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .opacity(viewState.state ? 1 : 0)
                )
            }
        }
        .overlay(statusOverlay)
        .mouseEvents(
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved]
        ) { event in
            let viewState = ViewStore(store.stateless)

            if event == .mouseMoved {
                viewState.send(.onMouseMoved)
            } else {
                viewState.send(.isHoveringPlayer(event == .mouseEntered))
            }
        }
        .onReceive(ViewStore(store).publisher.canShowPlayerOverlay) { showOverlay in
            if showOverlay {
                NSCursor.unhide()
            } else {
                NSCursor.setHiddenUntilMouseMoves(true)
            }

            NSWindow.ButtonType.allCases
                .forEach { button in
                    NSApp.mainWindow?
                        .standardWindowButton(button)?
                        .isHidden = !showOverlay
                }
        }
        .onReceive(ViewStore(store).publisher.playerIsFullScreen) { fullScreen in
            NSWindow.ButtonType.allCases
                .forEach { button in
                    NSApp.mainWindow?
                        .standardWindowButton(button)?
                        .isHidden = !fullScreen
                }
        }
        .onKeyDown { key in
            let viewStore = ViewStore(store)
            switch key {
            case .spaceBar:
                viewStore.send(.togglePlayback)
            case .leftArrow:
                viewStore.send(.backwardsTapped)
            case .rightArrow:
                viewStore.send(.forwardsTapped)
            case .downArrow:
                viewStore.send(.volume(to: viewStore.playerVolume - 0.10))
            case .upArrow:
                viewStore.send(.volume(to: viewStore.playerVolume + 0.10))
            }
        }
        .onDisappear {
            NSWindow.ButtonType.allCases
                .forEach { button in
                    NSApp.mainWindow?
                        .standardWindowButton(button)?
                        .isHidden = false
                }
            NSCursor.unhide()
        }
    }
}

// MARK: Status Overlay

extension AnimePlayerView {
    @ViewBuilder
    var statusOverlay: some View {
        WithViewStore(store) { state in
            state.status
        } content: { viewState in
            if viewState.state == .loading {
                loadingView
            } else if viewState.state == .paused || viewState.state == .replay {
                Button {
                    viewState.send(viewState.state == .paused ? .togglePlayback : .replayTapped)
                } label: {
                    Image(systemName: viewState.state == .paused ? "play.fill" : "arrow.counterclockwise")
                        .font(.title.bold())
                        .foregroundColor(Color.white)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
        }
    }
}

// MARK: Top Player Items

extension AnimePlayerView {
    @ViewBuilder
    var topPlayerItems: some View {
        HStack(alignment: .center) {
            dismissButton
            animeInfoView
            Spacer()
            videoGravityButton
            pipButton
            airplayButton
        }
        .frame(maxWidth: .infinity)
        .transition(.opacity)
    }

    @ViewBuilder
    var pipButton: some View {
        WithViewStore(store) { state in
            state.playerPiPStatus == .didStart
        } content: { viewStore in
            Button {
                viewStore.send(.togglePictureInPicture)
            } label: {
                Image(
                    systemName: viewStore.state ? "rectangle.center.inset.filled" : "rectangle.inset.bottomright.filled"
                )
                .font(.title2.bold())
                .contentShape(Rectangle())
                .foregroundColor(Color.white)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: Episodes

extension AnimePlayerView {
    @ViewBuilder
    var episodesOverlay: some View {
        WithViewStore(
            store,
            observe: EpisodesOverlayViewState.init
        ) { viewState in
            if viewState.isVisible, !viewState.episodes.isEmpty {
                LazyVStack(alignment: .leading) {
                    Text("Up Next")
                        .font(.title2.bold())
                        .padding(.horizontal, 24)

                    ScrollViewReader { proxy in
                        ScrollView(
                            .horizontal,
                            showsIndicators: true
                        ) {
                            LazyHStack(alignment: .bottom) {
                                ForEach(viewState.episodes) { episode in
                                    ThumbnailItemBigView(
                                        episode: episode,
                                        progress: viewState.episodesStore.first { $0.number == episode.number }?
                                            .progress,
                                        nowPlaying: episode.id == viewState.selectedEpisode,
                                        progressSize: 8
                                    )
                                    .frame(height: 200)
                                    .onTapGesture {
                                        if viewState.selectedEpisode != episode.id {
                                            viewState.send(
                                                .stream(
                                                    .selectEpisode(episode.id)
                                                )
                                            )
                                        }
                                    }
                                    .id(episode.id)
                                }
                            }
                            .padding([.horizontal, .bottom], 24)
                            .onAppear {
                                proxy.scrollTo(viewState.selectedEpisode, anchor: .leading)
                                viewState.send(.pause)
                            }
                            .onDisappear(perform: {
                                viewState.send(.play)
                            })
                            .onChange(
                                of: viewState.selectedEpisode
                            ) { newValue in
                                withAnimation {
                                    proxy.scrollTo(newValue, anchor: .leading)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: Bottom Player Items

extension AnimePlayerView {
    @ViewBuilder
    var bottomPlayerItems: some View {
        VStack {
            progressView
            HStack(spacing: 20) {
                playStateView
                volumeButton
                nextEpisodeButton
                durationView
                Spacer()
                subtitlesButton
                    .popover(
                        store.scope { state in
                            state.showSubtitlesOverlay
                        }
                    ) {
                        .closeSidebar
                    } content: {
                        sidebarOverlay
                            .frame(height: 300)
                    }
                episodesButton
                settingsButton
                    .popover(
                        store.scope { state in
                            state.showSettingsOverlay
                        }
                    ) {
                        .closeSidebar
                    } content: {
                        sidebarOverlay
                            .frame(height: 300)
                    }
                fullscreenButton
            }
        }
    }

    @ViewBuilder
    var playStateView: some View {
        WithViewStore(store) { state in
            state.playerStatus == .playback(.playing)
        } content: { viewState in
            Button {
                viewState.send(.togglePlayback)
            } label: {
                Image(systemName: viewState.state ? "pause.fill" : "play.fill")
                    .font(.title2.bold())
                    .contentShape(Rectangle())
                    .foregroundColor(Color.white)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        }
    }

    @ViewBuilder
    var progressView: some View {
        WithViewStore(
            store,
            observe: ProgressViewState.init
        ) { viewState in
            SeekbarView(
                progress: viewState.binding(
                    get: { $0.isLoaded ? $0.progress : 0 },
                    send: { .seeking(to: $0) }
                ),
                buffered: viewState.state.buffered,
                padding: 6
            ) { isEditing in
                viewState.send(isEditing ? .startSeeking : .stopSeeking)
            }
            .frame(height: 20)
            .disabled(!viewState.isLoaded)
        }
    }

    @ViewBuilder
    var durationView: some View {
        WithViewStore(
            store,
            observe: ProgressViewState.init
        ) { viewState in
            HStack(spacing: 4) {
                Text(
                    viewState.progressWithDuration?.timeFormatted ?? "--:--"
                )
                Text("/")
                Text(
                    viewState.isLoaded ? viewState.duration.timeFormatted : "--:--"
                )
            }
            .foregroundColor(.white)
            .font(.body.bold().monospacedDigit())
        }
    }

    private enum VolumeViewState: Equatable {
        case muted
        case low
        case mid
        case high

        init(_ state: AnimePlayerReducer.State) {
            if state.playerProgress > 2 / 3 {
                self = .high
            } else if state.playerVolume > 1 / 3 {
                self = .mid
            } else if state.playerVolume > 0 {
                self = .low
            } else {
                self = .muted
            }
        }

        var image: String {
            // TODO: Fix since this bugs the volume slider
            switch self {
            //            case .muted:
            //                return "speaker.slash.fill"
            //            case .low:
            //                return "speaker.wave.1.fill"
            //            case .mid:
            //                return "speaker.wave.2.fill"
            //            case .high:
            default:
                return "speaker.wave.3.fill"
            }
        }
    }

    @ViewBuilder
    var volumeButton: some View {
        HStack {
            WithViewStore(
                store,
                observe: VolumeViewState.init
            ) { viewState in
                Image(systemName: viewState.image)
                    .font(.title2.bold())
                    .contentShape(Rectangle())
                    .foregroundColor(Color.white)
            }

            WithViewStore(
                store,
                observe: \.playerVolume
            ) { viewState in
                SeekbarView(
                    progress: viewState.binding(
                        get: { $0 },
                        send: { .volume(to: $0) }
                    ),
                    padding: 0
                )
                .frame(
                    width: 75,
                    height: 6
                )
            }
        }
    }

    @ViewBuilder
    var fullscreenButton: some View {
        WithViewStore(store) { state in
            state.playerIsFullScreen
        } content: { viewState in
            Button {
                NSApp.mainWindow?.toggleFullScreen(nil)
            } label: {
                Image(
                    systemName: viewState
                        .state ? "arrow.down.right.and.arrow.up.left" : "arrow.up.backward.and.arrow.down.forward"
                )
                .font(.title2.bold())
                .foregroundColor(Color.white)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        }
    }
}

struct VideoPlayerViewMacOS_Previews: PreviewProvider {
    static var previews: some View {
        AnimePlayerView(
            store: .init(
                initialState: .init(
                    player: .init(),
                    anime: Anime.narutoShippuden.eraseAsRepresentable(),
                    stream: .init(
                        animeId: Anime.narutoShippuden.id,
                        episodeId: 0,
                        availableProviders: .init(items: []),
                        streamingProviders: []
                    )
                ),
                reducer: AnimePlayerReducer()
            )
        )
    }
}

extension NSWindow.ButtonType: CaseIterable {
    public static var allCases: [NSWindow.ButtonType] {
        [.closeButton, .zoomButton, .miniaturizeButton, .documentIconButton, .documentVersionsButton, .toolbarButton]
    }
}

extension AnimePlayerReducer.State {
    var canShowPlayerOverlay: Bool {
        showPlayerOverlay || playerStatus == .playback(.paused) || selectedSidebar != nil
    }

    var showSettingsOverlay: Bool {
        if case .settings = selectedSidebar {
            return true
        }
        return false
    }

    var showSubtitlesOverlay: Bool {
        if case .subtitles = selectedSidebar {
            return true
        }
        return false
    }
}
#endif

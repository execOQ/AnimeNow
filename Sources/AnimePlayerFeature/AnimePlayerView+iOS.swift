//
//  AnimePlayerView+iOS.swift
//  Anime Now! (iOS)
//
//  Created by ErrorErrorError on 10/16/22.
//

#if os(iOS)
import AVFoundation
import ComposableArchitecture
import SharedModels
import SwiftUI
import ViewComponents

// MARK: Player Controls Overlay

extension AnimePlayerView {
    @ViewBuilder
    var playerControlsOverlay: some View {
        WithViewStore(
            store,
            observe: \.showPlayerOverlay
        ) { viewState in
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    if viewState.state {
                        topPlayerItems
                    }
                    Spacer()
                    skipButton
                    if viewState.state {
                        bottomPlayerItems
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
                .padding(safeAreaInsetPadding(proxy))
                .ignoresSafeArea()
                .background(
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .opacity(viewState.state ? 1 : 0)
                )
            }
        }
        .overlay(statusOverlay)
        .overlay(
            sidebarOverlay
                .padding()
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .trailing
                )
                .gesture(
                    DragGesture()
                        .onEnded { value in
                            // Drag right
                            if value.startLocation.x < value.location.x {
                                ViewStore(store.stateless).send(.closeSidebar)
                            }
                        }
                )
        )
        .overlay(episodesOverlay)
    }

    func safeAreaInsetPadding(_ proxy: GeometryProxy) -> Double {
        let safeArea = max(proxy.safeAreaInsets.leading, proxy.safeAreaInsets.trailing)

        if safeArea != 0 {
            return safeArea
        } else {
            return 24
        }
    }
}

// MARK: Player Status

extension AnimePlayerView {
    private struct VideoStatusViewState: Equatable {
        let status: AnimePlayerReducer.State.Status?
        let showingPlayerControls: Bool
        let loaded: Bool
        let skipInterval: Int

        init(_ state: AnimePlayerReducer.State) {
            self.status = state.status
            self.showingPlayerControls = state.showPlayerOverlay
            self.loaded = state.playerDuration != 0
            self.skipInterval = state.skipInterval
        }

        var canShowSeek: Bool {
            switch status {
            case .error:
                return false
            default:
                return showingPlayerControls
            }
        }
    }

    @ViewBuilder
    var statusOverlay: some View {
        WithViewStore(
            store,
            observe: VideoStatusViewState.init
        ) { viewState in
            HStack(spacing: 24) {
                if viewState.canShowSeek {
                    Image(systemName: "gobackward.\(viewState.skipInterval)")
                        .frame(width: 48, height: 48)
                        .foregroundColor(viewState.state.loaded ? .white : .gray)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewState.send(.backwardsTapped)
                        }
                        .disabled(!viewState.state.loaded)
                }

                switch viewState.status {
                case .some(.loading):
                    loadingView
                case .some(.playing), .some(.paused):
                    if viewState.showingPlayerControls {
                        Image(systemName: viewState.status == .playing ? "pause.fill" : "play.fill")
                            .font(.title.bold())
                            .frame(width: 48, height: 48)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewState.send(.togglePlayback)
                            }
                            .foregroundColor(Color.white)
                    }
                case .some(.replay):
                    Image(systemName: "arrow.counterclockwise")
                        .frame(width: 48, height: 48)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewState.send(.replayTapped)
                        }
                        .foregroundColor(Color.white)
                default:
                    EmptyView()
                }

                if viewState.canShowSeek {
                    Image(systemName: "goforward.\(viewState.skipInterval)")
                        .frame(width: 48, height: 48)
                        .contentShape(Rectangle())
                        .foregroundColor(
                            viewState.state.loaded && viewState.status != .replay ? .white : .gray
                        )
                        .onTapGesture {
                            viewState.send(.forwardsTapped)
                        }
                        .disabled(!viewState.state.loaded || viewState.status == .replay)
                }
            }
            .font(.title)
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
            airplayButton
            videoGravityButton
            subtitlesButton
            episodesButton
            settingsButton
        }
        .frame(maxWidth: .infinity)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: Episodes Overlay

extension AnimePlayerView {
    @ViewBuilder
    var episodesOverlay: some View {
        WithViewStore(
            store,
            observe: EpisodesOverlayViewState.init
        ) { viewState in
            if viewState.isVisible {
                GeometryReader { reader in
                    VStack {
                        HStack {
                            Button {
                                viewState.send(.closeSidebar)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.body.bold())
                                    .padding(12)
                                    .background(Color(white: 0.12))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, safeAreaInsetPadding(reader))

                            Spacer()
                        }

                        if !viewState.episodes.isEmpty {
                            ScrollViewReader { proxy in
                                ScrollView(
                                    .horizontal,
                                    showsIndicators: false
                                ) {
                                    LazyHStack {
                                        ForEach(viewState.episodes) { episode in
                                            ThumbnailItemBigView(
                                                episode: episode,
                                                progress: viewState.episodesStore.first { $0.number == episode.number }?
                                                    .progress,
                                                nowPlaying: episode.id == viewState.selectedEpisode,
                                                progressSize: 8
                                            )
                                            .onTapGesture {
                                                if viewState.selectedEpisode != episode.id {
                                                    viewState.send(.stream(.selectEpisode(episode.id)))
                                                }
                                            }
                                            .id(episode.id)
                                            .frame(
                                                height: reader.size.height / 2
                                            )
                                        }
                                    }
                                    .padding(.horizontal, safeAreaInsetPadding(reader))
                                    .onAppear {
                                        proxy.scrollTo(viewState.selectedEpisode, anchor: .center)
                                        viewState.send(.pause)
                                    }
                                    .onDisappear {
                                        viewState.send(.play)
                                    }
                                    .onChange(
                                        of: viewState.selectedEpisode
                                    ) { newValue in
                                        withAnimation {
                                            proxy.scrollTo(newValue, anchor: .center)
                                        }
                                    }
                                }
                            }
                        }

                        Spacer()
                    }
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )
                    .padding(.vertical, safeAreaInsetPadding(reader))
                    .ignoresSafeArea()
                    .background(
                        Color.black.opacity(0.5)
                            .ignoresSafeArea()
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func selectedEpisodeOverlay(_ selected: Bool) -> some View {
        if selected {
            Text("Now Playing")
                .font(.caption2.weight(.heavy))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white)
                .foregroundColor(.black)
                .clipShape(Capsule())
                .shadow(
                    color: .black.opacity(0.5),
                    radius: 16,
                    x: 0,
                    y: 0
                )
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .bottomLeading
                )
                .padding(6)
        }
    }
}

// MARK: Bottom Player Items

extension AnimePlayerView {
    @ViewBuilder
    var bottomPlayerItems: some View {
        seekbarAndDurationView
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: Seekbar and Duration Items

extension AnimePlayerView {
    @ViewBuilder
    var seekbarAndDurationView: some View {
        WithViewStore(
            store.scope(
                state: ProgressViewState.init
            )
        ) { viewState in
            HStack(
                spacing: 12
            ) {
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
                .font(.footnote.bold().monospacedDigit())
            }
            .disabled(!viewState.isLoaded)
        }
    }
}

struct VideoPlayerViewiOS_Previews: PreviewProvider {
    static var previews: some View {
        if #available(iOS 15.0, macOS 12.0, *) {
            AnimePlayerView(
                store: .init(
                    initialState: .init(
                        player: .init(),
                        anime: Anime.narutoShippuden.eraseAsRepresentable(),
                        stream: .init(
                            animeId: Anime.narutoShippuden.id,
                            episodeId: 0,
                            availableProviders: .init(items: [])
                        )
                    ),
                    reducer: AnimePlayerReducer()
                )
            )
            .previewInterfaceOrientation(.landscapeLeft)
        } else {
            // Fallback on earlier versions
        }
    }
}
#endif

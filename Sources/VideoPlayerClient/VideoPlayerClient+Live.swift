//
//  VideoPlayerClient+Live.swift
//  VideoPlayerClient
//
//  Created by ErrorErrorError on 12/23/22.
//

import AnyPublisherStream
import AVFAudio
import AVFoundation
import AVKit
import Combine
import Foundation
import ImageDatabaseClient
import Logger
import MediaPlayer

public extension VideoPlayerClient {
    static let liveValue: Self = {
        let wrapper = PlayerWrapper()

        return .init(
            status: { wrapper.statusPublisher.stream },
            progress: {
                .init { continuation in
                    let timerObserver = wrapper.player.addPeriodicTimeObserver(
                        forInterval: .init(
                            seconds: 0.25,
                            preferredTimescale: 60
                        ),
                        queue: .main
                    ) { _ in
                        continuation.yield(wrapper.player.playProgress)
                    }

                    continuation.onTermination = { _ in
                        wrapper.player.removeTimeObserver(timerObserver)
                    }
                }
            },
            execute: { action in wrapper.handle(action) },
            player: { wrapper.player }
        )
    }()
}

// MARK: - PlayerWrapper

// swiftlint:disable type_body_length
private class PlayerWrapper {
    let player = AVQueuePlayer()
    let statusPublisher = CurrentValueSubject<VideoPlayerClient.Status, Never>(.idle)

    #if os(iOS)
    private let session = AVAudioSession.sharedInstance()
    #endif

    private var playerItemCancellables = Set<AnyCancellable>()
    private var cancellables = Set<AnyCancellable>()
    private var timerObserver: Any?

    private let nowPlayingOperationQueue = OperationQueue()

    private var status: VideoPlayerClient.Status {
        get { statusPublisher.value }
        set {
            if statusPublisher.value != newValue {
                statusPublisher.value = newValue
            }
        }
    }

    init() {
        configureInit()
    }

    // swiftlint:disable cyclomatic_complexity
    private func configureInit() {
        player.automaticallyWaitsToMinimizeStalling = true
        player.preventsDisplaySleepDuringVideoPlayback = true
        player.actionAtItemEnd = .pause

        #if os(iOS)
        try? session.setCategory(
            .playback,
            mode: .moviePlayback,
            policy: .longFormVideo
        )
        #endif

        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
            .compactMap { $0.object as? AVPlayerItem }
            .filter { [unowned self] item in item == self.player.currentItem }
            .sink { [unowned self] _ in
                self.updateStatus(.finished)
            }
            .store(in: &cancellables)

        // Observe Player

        player.publisher(
            for: \.timeControlStatus
        )
        .dropFirst()
        .sink { [unowned self] status in
            switch status {
            case .waitingToPlayAtSpecifiedRate:
                if let waiting = player.reasonForWaitingToPlay {
                    switch waiting {
                    case .noItemToPlay:
                        self.updateStatus(.idle)

                    case .toMinimizeStalls:
                        self.updateStatus(.playback(.buffering))

                    default:
                        break
                    }
                }

            case .paused:
                self.updateStatus(.playback(.paused))

            case .playing:
                self.updateStatus(.playback(.playing))

            default:
                break
            }
        }
        .store(in: &cancellables)

        player.publisher(
            for: \.currentItem
        )
        .sink { [unowned self] item in
            self.observe(playerItem: item)
        }
        .store(in: &cancellables)

        timerObserver = player.addPeriodicTimeObserver(
            forInterval: .init(
                seconds: 1,
                preferredTimescale: 1
            ),
            queue: .main
        ) { [unowned self] _ in
            self.updateNowPlaying()
        }

        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self else {
                return .commandFailed
            }

            if self.player.rate == 0.0 {
                self.player.play()
                return .success
            }

            return .commandFailed
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self else {
                return .commandFailed
            }
            if self.player.rate > 0 {
                self.player.pause()
                return .success
            }

            return .commandFailed
        }

        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }

            guard let self else {
                return .commandFailed
            }

            if self.player.totalDuration > 0.0 {
                let time = CMTime(seconds: event.positionTime, preferredTimescale: 1)
                self.player.seek(to: time)
                return .success
            }

            return .commandFailed
        }

        commandCenter.skipForwardCommand.addTarget { [weak self] event in
            guard let event = event as? MPSkipIntervalCommandEvent else {
                return .commandFailed
            }

            guard let self else {
                return .commandFailed
            }

            if self.player.totalDuration > 0.0 {
                let time = CMTime(
                    seconds: min(self.player.currentDuration + event.interval, self.player.totalDuration),
                    preferredTimescale: 1
                )
                self.player.seek(to: time)
                return .success
            }

            return .commandFailed
        }

        commandCenter.skipBackwardCommand.addTarget { [weak self] event in
            guard let event = event as? MPSkipIntervalCommandEvent else {
                return .commandFailed
            }

            guard let self else {
                return .commandFailed
            }

            if self.player.totalDuration > 0.0 {
                let time = CMTime(
                    seconds: max(self.player.currentDuration - event.interval, 0.0),
                    preferredTimescale: 1
                )
                self.player.seek(to: time)
                return .success
            }

            return .commandFailed
        }
    }

    private func observe(playerItem: AVPlayerItem?) {
        guard let playerItem else {
            playerItemCancellables.removeAll()
            updateStatus(.idle)
            return
        }

        playerItem.publisher(
            for: \.status
        )
        .removeDuplicates()
        .dropFirst()
        .sink { [unowned self] status in
            switch status {
            case .unknown:
                self.updateStatus(.idle)

            case .readyToPlay:
                // TODO: Test if duration is updated
//                self.updateStatus(.loaded(duration: playerItem.totalDuration))
                break

            case .failed:
                Logger.log(.error, "Player error: - \(playerItem.errorLog().debugDescription)")
                self.updateStatus(.error)

            default:
                break
            }
        }
        .store(in: &playerItemCancellables)

        playerItem.publisher(
            for: \.isPlaybackBufferEmpty
        )
        .dropFirst()
        .sink { [unowned self] bufferEmpty in
            if bufferEmpty {
                self.updateStatus(.playback(.buffering))
            }
        }
        .store(in: &playerItemCancellables)

        playerItem.publisher(
            for: \.isPlaybackLikelyToKeepUp
        )
        .dropFirst()
        .sink { [unowned self] canKeepUp in
            if canKeepUp, self.status == .playback(.buffering) {
                self.updateStatus(.playback(self.player.rate > 0 ? .playing : .paused))
            }
        }
        .store(in: &playerItemCancellables)

        playerItem.publisher(for: \.duration)
            .dropFirst()
            .sink { [unowned self] duration in
                if duration.isValid, duration.seconds > 0.0 {
                    self.updateStatus(.loaded(duration: duration.seconds))
                }
            }
            .store(in: &playerItemCancellables)
    }

    private func updateNowPlaying(_ metadata: VideoPlayerClient.Metadata? = nil) {
        nowPlayingOperationQueue.addOperation { [unowned self] in
            let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
            var nowPlayingInfo = nowPlayingInfoCenter.nowPlayingInfo ?? [:]

            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = self.player.currentItem?.totalDuration ?? self.player
                .totalDuration
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = self.player.currentItem?
                .currentDuration ?? self.player.currentDuration
            nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = self.player.rate

            if let metadata {
                nowPlayingInfo[MPMediaItemPropertyTitle] = metadata.videoTitle
                nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = metadata.videoAuthor
                nowPlayingInfo[MPMediaItemPropertyAlbumArtist] = "Anime Now!"
                if let imageURL = metadata.thumbnail, let image = ImageDatabase.shared.cachedImage(imageURL) {
                    let media = MPMediaItemArtwork(
                        boundsSize: image.size
                    ) { size in
                        #if os(macOS)
                        // swiftlint:disable force_cast
                        let copy = image.copy() as! PlatformImage
                        copy.size = size
                        #elseif os(iOS)
                        let copy = image.resizeImageTo(size: size) ?? .init()
                        #endif
                        return copy
                    }
                    nowPlayingInfo[MPMediaItemPropertyArtwork] = media
                } else {
                    nowPlayingInfo[MPMediaItemPropertyArtwork] = nil
                }
            }

            nowPlayingInfoCenter.nowPlayingInfo = nowPlayingInfo

            #if os(macOS)
            switch self.status {
            case .idle:
                MPNowPlayingInfoCenter.default().playbackState = .stopped
            case .loading:
                MPNowPlayingInfoCenter.default().playbackState = .playing
            case .loaded:
                MPNowPlayingInfoCenter.default().playbackState = .playing
            case .playback(.buffering):
                MPNowPlayingInfoCenter.default().playbackState = .playing
            case .playback(.playing):
                MPNowPlayingInfoCenter.default().playbackState = .playing
            case .playback(.paused):
                MPNowPlayingInfoCenter.default().playbackState = .paused
            case .error:
                MPNowPlayingInfoCenter.default().playbackState = .unknown
            case .finished:
                MPNowPlayingInfoCenter.default().playbackState = .paused
            }
            #endif
        }
    }

    func handle(_ action: VideoPlayerClient.Action) {
        switch action {
        case let .play(payload):
            let videoPlayerItem = VideoPlayerItem(payload)

            player.replaceCurrentItem(with: videoPlayerItem)
            #if os(iOS)
            try? session.setActive(true)
            #endif
            updateStatus(.loading)
            updateNowPlaying(payload.metadata)

        case .resume:
            if status.canChangePlayback {
                player.play()
            }

        case .pause:
            if status.canChangePlayback {
                player.pause()
            }

        case let .seekTo(progress):
            if status.canChangePlayback {
                let time = CMTime(
                    seconds: round(progress * player.totalDuration),
                    preferredTimescale: 1
                )

                player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
            }

        case let .volume(volume):
            player.volume = Float(volume)

        case .clear:
            player.pause()
            player.removeAllItems()
            playerItemCancellables.removeAll()
            updateStatus(.idle)
            #if os(iOS)
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            #endif
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            #if os(macOS)
            MPNowPlayingInfoCenter.default().playbackState = .unknown
            #endif
        }
    }

    private func updateStatus(_ newStatus: VideoPlayerClient.Status) {
        let oldStatus = status

        guard oldStatus != newStatus else {
            return
        }

        guard newStatus != .idle, newStatus != .error else {
            status = newStatus
            return
        }

        switch (oldStatus, newStatus) {
        case (.idle, .loading), (.idle, .loaded):
            status = newStatus

        case (.loading, .loaded):
            status = newStatus

        case (.loaded, .playback), (.loaded, .loaded):
            status = newStatus

        case (.playback, .finished), (.playback, .playback):
            status = newStatus

        case (.finished, .playback(.playing)), (.finished, .playback(.buffering)):
            status = newStatus

        default:
            break
        }
    }
}

extension VideoPlayerClient.Status {
    var canChangePlayback: Bool {
        switch self {
        case .loaded, .playback, .finished:
            return true
        default:
            return false
        }
    }
}

#if os(iOS)
extension UIImage {
    func resizeImageTo(size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        draw(in: CGRect(origin: CGPoint.zero, size: size))
        if let resizedImage = UIGraphicsGetImageFromCurrentImageContext() {
            UIGraphicsEndImageContext()
            return resizedImage
        }
        return nil
    }
}
#endif

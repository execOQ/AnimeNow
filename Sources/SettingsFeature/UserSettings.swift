//
//  UserSettings.swift
//
//
//  Created by ErrorErrorError on 1/16/23.
//
//

import Foundation
import Utilities

// MARK: - UserSettings

public struct UserSettings: Codable, Equatable {
    public var preferredProvider: String?
    @Defaultable<DiscordSettings>
    public var discordSettings: DiscordSettings
    @Defaultable<TrackingSettings>
    public var trackingSettings: TrackingSettings
    @Defaultable<VideoSetings>
    public var videoSettings: VideoSetings

    public init(
        preferredProvider: String? = nil,
        discordSettings: UserSettings.DiscordSettings = .init(),
        trackingSettings: UserSettings.TrackingSettings = .init(),
        videoSettings: UserSettings.VideoSetings = .init()
    ) {
        self.preferredProvider = preferredProvider
        self.discordSettings = discordSettings
        self.trackingSettings = trackingSettings
        self.videoSettings = videoSettings
    }
}

// MARK: UserSettings.DiscordSettings

public extension UserSettings {
    struct DiscordSettings: Codable, Equatable, DefaultValueProvider {
        public static let `default` = Self()

        @Defaultable<True>
        public var discordEnabled: Bool

        public init(discordEnabled: Bool = true) {
            self.discordEnabled = discordEnabled
        }
    }
}

// MARK: UserSettings.VideoSetings

public extension UserSettings {
    struct VideoSetings: Codable, Equatable, DefaultValueProvider {
        public static let `default` = Self()

        @Defaultable<True>
        public var showTimeStamps: Bool
        @Defaultable<True>
        public var doubleTapToSeek: Bool
        @Defaultable<SkipTimeDefault>
        public var skipTime: Int

        public init(
            showTimeStamps: Bool = true,
            doubleTapToSeek: Bool = true,
            skipTime: Int = 15
        ) {
            self.showTimeStamps = showTimeStamps
            self.doubleTapToSeek = doubleTapToSeek
            self.skipTime = skipTime
        }
    }

    enum SkipTimeDefault: DefaultValueProvider {
        public static var `default`: Int = 15
    }
}

// MARK: UserSettings.TrackingSettings

public extension UserSettings {
    struct TrackingSettings: Codable, Equatable, DefaultValueProvider {
        public static var `default` = Self()

        // TODO: Add more options to tracking settings

        @Defaultable<True>
        public var autoTrackEpisodes: Bool

        public init(autoTrackEpisodes: Bool = true) {
            self.autoTrackEpisodes = autoTrackEpisodes
        }
    }
}

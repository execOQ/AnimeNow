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
    public var discordEnabled: Bool
    @Defaultable<VideoSetings>
    public var videoSettings: VideoSetings

    public init(
        preferredProvider: String? = nil,
        discordEnabled: Bool = false
    ) {
        self.preferredProvider = preferredProvider
        self.discordEnabled = discordEnabled
    }
}

// MARK: UserSettings.VideoSetings

public extension UserSettings {
    struct VideoSetings: Codable, Equatable, DefaultValueProvider {
        public static let `default` = UserSettings.VideoSetings()

        public var showTimeStamps: Bool
        public var doubleTapToSeek: Bool
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
}

//
//  TrackingListClient+Live.swift
//
//
//  Created by ErrorErrorError on 2/16/23.
//
//

import Dependencies
import Foundation

public extension TrackingListClient {
    static var liveValue: TrackingListClient {
        @Dependency(\.apiClient)
        var apiClient

        @Dependency(\.anilistClient)
        var anilistClient

        @Dependency(\.kitsuClient)
        var kitsuClient

        @Dependency(\.myanimelistClient)
        var myanimelistClient

        return .init { id, episodeNumber in
            let response = try await apiClient.request(.arm(.ids(id, "anilist")))

            await withThrowingTaskGroup(of: Void.self) { group in
                if let anilistId = response.anilist {
                    group.addTask {
                        try await anilistClient.sync(anilistId, episodeNumber)
                    }
                }

                if let kitsuId = response.kitsu {
                    group.addTask {
                        try await kitsuClient.sync(kitsuId.description, episodeNumber)
                    }
                }

                if let myanimelistId = response.myanimelist {
                    group.addTask {
                        try await myanimelistClient.sync(myanimelistId, episodeNumber)
                    }
                }
            }
        }
    }
}

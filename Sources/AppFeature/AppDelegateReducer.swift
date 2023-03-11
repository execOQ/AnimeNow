//
//  AppDelegateReducer.swift
//
//  Created by ErrorErrorError on 11/1/22.
//
//

import ComposableArchitecture
import DatabaseClient
import DiscordClient
import DownloaderClient
import FileClient
import SettingsFeature
import SharedModels
import TrackingListClient
import UserDefaultsClient
import Utilities

// MARK: - AppDelegateReducer

public struct AppDelegateReducer: ReducerProtocol {
    public typealias State = UserSettings

    public enum Action: Equatable {
        case appDidFinishLaunching
        case appDidEnterBackground
        case appWillTerminate
        case userSettingsLoaded(Loadable<UserSettings>)
    }

    public var body: some ReducerProtocol<State, Action> {
        Reduce(self.core)
    }

    @Dependency(\.fileClient)
    var fileClient
    @Dependency(\.discordClient)
    var discordClient
    @Dependency(\.databaseClient)
    var databaseClient
    @Dependency(\.downloaderClient)
    var downloaderClient
    @Dependency(\.userDefaultsClient)
    var userDefaultsClient
    @Dependency(\.trackingListClient)
    var trackingListClient
}

extension AppDelegateReducer {
    func core(state: inout State, action: Action) -> EffectTask<Action> {
        switch action {
        case .appDidFinishLaunching:
            return .run { send in
                await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        if !userDefaultsClient.get(.hasClearedAllVideos) {
                            // Remove all videos from database on first time opening app launch to sync with
                            // store.
                            await downloaderClient.reset()
                            await userDefaultsClient.set(.hasClearedAllVideos, value: true)
                        }
                    }

                    group.addTask {
                        for title in CollectionStore.Title.allCases where try await databaseClient
                            .fetch(CollectionStore.all.where(\CollectionStore.title == title)).first == nil {
                            let collection = CollectionStore(title: title)
                            try await databaseClient.insert(collection)
                        }
                    }

                    group.addTask {
                        await send(
                            .userSettingsLoaded(
                                .init { try await fileClient.loadUserSettings() }
                            )
                        )
                    }
                }
            }

        case let .userSettingsLoaded(result):
            state = result.value ?? state
            return .run { [state] _ in
                try await discordClient.setActive(state.discordSettings.discordEnabled)
            }

        default:
            break
        }

        return .none
    }
}

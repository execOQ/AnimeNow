//
//  SettingsReducer.swift
//  Anime Now!
//
//  Created by ErrorErrorError on 9/8/22.
//  Copyright © 2022. All rights reserved.
//

import APIClient
import Build
import ComposableArchitecture
import DiscordClient
import FileClient
import Foundation
import ImageDatabaseClient
import Logger
import SharedModels
import SwiftUI
import TrackingListClient
import UserDefaultsClient
import Utilities
import ViewComponents

// MARK: - SettingsReducer

public struct SettingsReducer: ReducerProtocol {
    public init() {}

    public struct State: Equatable {
        // MARK: Anime Providers

        public var animeProviders: Loadable<[ProviderInfo]>

        // MARK: Discord Properties

        public var supportsDiscord: Bool
        public var discordStatus: DiscordClient.Status

        public var buildVersion: String

        // MARK: Storage Settings

        public var imageCacheUsage: Int
        public var imageCacheCapacity: Int

        // MARK: Account Services

        var anilistUser: AuthState<AniListClient.User>
        var myanimelistUser: AuthState<MyAnimeListClient.User>
        var kitsuUser: AuthState<KitsuClient.User>

        // MARK: User Settings

        @BindingState
        public var userSettings: UserSettings

        #if os(iOS)
        var logoutAlert: ConfirmationDialogState<LogoutAction>?
        #else
        var logoutAlert: AlertState<LogoutAction>?
        #endif

        public init(
            animeProviders: Loadable<[ProviderInfo]> = .idle,
            supportsDiscord: Bool = false,
            discordStatus: DiscordClient.Status = DiscordClient.Status.offline,
            buildVersion: String = "Unknown",
            imageCacheUsage: Int = 0,
            imageCacheCapacity: Int = 0,
            anilistUser: AuthState<AniListClient.User> = AuthState<AniListClient.User>.unauthenticated,
            myanimelistUser: AuthState<MyAnimeListClient.User> = AuthState<MyAnimeListClient.User>.unauthenticated,
            kitsuUser: AuthState<KitsuClient.User> = AuthState<KitsuClient.User>.unauthenticated,
            userSettings: UserSettings = UserSettings()
        ) {
            self.animeProviders = animeProviders
            self.supportsDiscord = supportsDiscord
            self.discordStatus = discordStatus
            self.buildVersion = buildVersion
            self.imageCacheUsage = imageCacheUsage
            self.imageCacheCapacity = imageCacheCapacity
            self.anilistUser = anilistUser
            self.myanimelistUser = myanimelistUser
            self.userSettings = userSettings
        }
    }

    public enum Action: BindableAction, Equatable {
        case onAppear
        case refetchImageCache
        case resetImageCache
        case anilistLogin
        case anilist(AuthState<AniListClient.User>)
        case myanimelistLogin
        case myanimelistLogout
        case myanimelist(AuthState<MyAnimeListClient.User>)
        case kitsuLogin
        case kitsuLogout
        case kitsu(AuthState<KitsuClient.User>)
        case discordStatus(DiscordClient.Status)
        case binding(BindingAction<State>)
    }

    @Dependency(\.anilistClient)
    var anilistClient

    @Dependency(\.build)
    var build

    @Dependency(\.discordClient)
    var discordClient

    @Dependency(\.fileClient)
    var fileClient

    @Dependency(\.kitsuClient)
    var kitsuClient

    @Dependency(\.myanimelistClient)
    var myanimelistClient

    @Dependency(\.userDefaultsClient)
    var userDefaultsClient

    public var body: some ReducerProtocol<State, Action> {
        CombineReducers {
            BindingReducer()
            Reduce(core)
        }
        .onChange(of: \.userSettings) { userSettings, _, _ in
            struct SaveDebounceID: Hashable {}

            return .run {
                try await withTaskCancellation(id: SaveDebounceID.self, cancelInFlight: true) {
                    try await fileClient.save(userSettings: userSettings)
                }
            }
        }
    }
}

extension SettingsReducer.State {
    var accounts: [AccountList] {
        [
            .init(
                name: "AniList",
                image: "anilist_logo",
                roundedLogo: false,
                description: "Track, discover, and share anime and manga with AniList.",
                authentication: anilistUser.map { user in
                    .init(
                        name: user.name,
                        profileImage: (user.avatar?.large ?? user.avatar?.large).flatMap { .init(string: $0) },
                        bannerImage: user.bannerImage.flatMap { .init(string: $0) },
                        episodesWatched: user.statistics?.anime.episodesWatched ?? 0
                    )
                },
                login: .anilistLogin,
                logout: .logoutAlert(.mal),
                palette: [
                    .init(red: 0.40392156, green: 0.423529411764706, blue: 0.454901960784314),
                    .init(red: 0.01, green: 0.56, blue: 0.83),
                    .init(red: 0.09, green: 0.13, blue: 0.17)
                ]
            ),
            .init(
                name: "MyAnimeList",
                image: "mal_logo",
                roundedLogo: true,
                description: "MyAnimeList is the world's most active online anime and manga community!",
                authentication: myanimelistUser.map { userInfo in
                    .init(
                        name: userInfo.name,
                        profileImage: userInfo.picture
                            .flatMap { .init(string: $0) },
                        bannerImage: nil,
                        episodesWatched: userInfo.anime_statistics?.num_episodes ?? 0
                    )
                },
                login: .myanimelistLogin,
                logout: .myanimelistLogout,
                palette: [
                    .init(red: 0.18, green: 0.32, blue: 0.64),
                    .init(red: 0.27, green: 0.27, blue: 0.27),
                    .init(red: 0.88, green: 0.91, blue: 0.96)
                ]
            ),
            .init(
                name: "Kitsu",
                image: "kitsu_logo",
                roundedLogo: false,
                description: "Discover and share anime you love on Kitsu, the largest social anime tracker!",
                authentication: kitsuUser.map { user in
                    .init(
                        name: user.name,
                        profileImage: user.avatarImage?.original.url,
                        bannerImage: user.bannerImage?.original.url,
                        episodesWatched: nil
                    )
                },
                login: .kitsuLogin,
                logout: .kitsuLogout,
                palette: [
                    .init(red: 0.19, green: 0.15, blue: 0.19),
                    .init(red: 0.55, green: 0.23, blue: 0.20),
                    .init(red: 0.97, green: 0.32, blue: 0.22)
                ]
            )
        ]
    }

    public var selectableAnimeProviders: Selectable<ProviderInfo> {
        .init(
            items: animeProviders.value ?? [],
            selected: userSettings.preferredProvider
        )
    }
}

extension SettingsReducer {
    struct DiscordClientStatusCancellable: Hashable {}

    private func core(state: inout State, action: Action) -> EffectTask<Action> {
        switch action {
        case .onAppear:
            state.buildVersion = "\(build.version()) (\(build.gitSha()))"
            return .merge(
                setupDiscord(&state),
                setupCache(&state),
                setupTrackers(&state)
            )

        case let .discordStatus(status):
            state.discordStatus = status

        case .resetImageCache:
            return .run { send in
                await ImageDatabase.shared.reset()
                await send(.refetchImageCache)
            }

        case .refetchImageCache:
            return setupCache(&state)

        case .anilistLogin:
            state.anilistUser = .authenticating
            return .run { send in
                do {
                    let user = try await anilistClient.logIn()
                    await send(.anilist(.authenticated(user)))
                } catch {
                    Logger.log(.debug, "Failed to log in with AniList: \(error)")
                    await send(.anilistLogout)
                }
            }

        case .anilistLogout:
            state.anilistUser = .unauthenticated
            return .run {
                await anilistClient.logOut()
            }

        case let .anilist(auth):
            state.anilistUser = auth

        case .myanimelistLogin:
            state.myanimelistUser = .authenticating
            return .run { send in
                do {
                    let user = try await myanimelistClient.logIn()
                    await send(.myanimelist(.authenticated(user)))
                } catch {
                    Logger.log(.debug, "Failed to log in with MyAnimeList: \(error)")
                    await send(.myanimelistLogout)
                }
            }

        case .myanimelistLogout:
            state.myanimelistUser = .unauthenticated
            return .run {
                await myanimelistClient.logOut()
            }

        case let .myanimelist(auth):
            state.myanimelistUser = auth

        case .kitsuLogin:
            state.kitsuUser = .authenticating
            return .run { send in
                do {
                    let user = try await kitsuClient.logIn()
                    await send(.kitsu(.authenticated(user)))
                } catch {
                    Logger.log(.debug, "Failed to log in with Kitsu: \(error)")
                    await send(.kitsuLogout)
                }
            }

        case .kitsuLogout:
            state.kitsuUser = .unauthenticated
            return .run {
                await kitsuClient.logOut()
            }

        case let .kitsu(auth):
            state.kitsuUser = auth

        case .binding(\.$userSettings.discordEnabled):
            let enabled = state.userSettings.discordEnabled

            return .run { _ in
                try await discordClient.setActive(enabled)
            }

        case .binding:
            break
        }
        return .none
    }

    private func setupDiscord(_ state: inout State) -> EffectTask<Action> {
        state.supportsDiscord = discordClient.isSupported
        if state.supportsDiscord {
            return .run { send in
                await withTaskCancellation(
                    id: DiscordClientStatusCancellable.self,
                    cancelInFlight: true
                ) {
                    for await status in discordClient.status() {
                        await send(.discordStatus(status))
                    }
                }
            }
        } else {
            return .none
        }
    }

    private func setupCache(_ state: inout State) -> EffectTask<Action> {
        state.imageCacheUsage = ImageDatabase.shared.diskUsage()
        state.imageCacheCapacity = ImageDatabase.shared.maxDiskCapacity()
        return .none
    }

    private func setupTrackers(_: inout State) -> EffectTask<Action> {
        .run { send in
            await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    if await anilistClient.loggedIn() {
                        await send(.anilist(.authenticating))
                        if let user = await anilistClient.user() {
                            await send(.anilist(.authenticated(user)))
                        } else {
                            await send(.anilist(.init { try await anilistClient.refreshUser() }))
                        }
                    } else {
                        await send(.anilist(.unauthenticated))
                    }
                }

                group.addTask {
                    if await myanimelistClient.loggedIn() {
                        await send(.myanimelist(.authenticating))
                        if let user = await myanimelistClient.user() {
                            await send(.myanimelist(.authenticated(user)))
                        } else {
                            await send(.myanimelist(.init { try await myanimelistClient.refreshUser() }))
                        }
                    } else {
                        await send(.myanimelist(.unauthenticated))
                    }
                }

                group.addTask {
                    if await kitsuClient.loggedIn() {
                        await send(.kitsu(.authenticating))
                        if let user = await kitsuClient.user() {
                            await send(.kitsu(.authenticated(user)))
                        } else {
                            await send(.kitsu(.init { try await kitsuClient.refreshUser() }))
                        }
                    } else {
                        await send(.kitsu(.unauthenticated))
                    }
                }
            }
        }
    }
}

public extension FileClient {
    func save(userSettings: UserSettings) async throws {
        try await save(userSettings, to: FileClient.userSettingsFileName)
    }

    func loadUserSettings() async throws -> UserSettings {
        try await load(UserSettings.self, from: FileClient.userSettingsFileName)
    }

    static let userSettingsFileName = "user-settings"
}

// MARK: - SettingsReducer.State.AccountList

public extension SettingsReducer.State {
    struct AccountList: Equatable {
        var name: String
        var image: String
        var roundedLogo: Bool
        var description: String
        var authentication: AuthState<User>
        var login: SettingsReducer.Action
        var logout: SettingsReducer.Action
        var palette: [Color]

        struct User: Equatable {
            let name: String
            let profileImage: URL?
            let bannerImage: URL?
            let episodesWatched: Int?
        }
    }
}

#if os(iOS)
extension AlertState {
    var confirmationState: ConfirmationDialogState<Action> {
        .init(
            title: title,
            titleVisibility: .automatic,
            message: message,
            buttons: buttons
        )
    }
}
#endif

//
//  KitsuClient.swift
//
//
//  Created by ErrorErrorError on 3/1/23.
//
//

import APIClient
import AuthenticationClient
import ComposableArchitecture
import FileClient
import Foundation
import Utilities

// MARK: - KitsuClient

public struct KitsuClient: TrackableList {
    public var name: String { "Kitsu" }
    public let initialize: @Sendable () async throws -> Void
    public let logIn: @Sendable () async throws -> User
    public let logOut: @Sendable ()
        async -> Void
    public let loggedIn: @Sendable ()
        async -> Bool
    public let refreshUser: @Sendable () async throws -> User
    public let user: @Sendable ()
        async -> User?
    public let userCollections: @Sendable () async throws -> Collections
    public let sync: @Sendable (String, Int?) async throws -> Void
}

public extension KitsuClient {
    typealias User = KitsuModels.Profile
    typealias Collections = KitsuModels.Library
    fileprivate typealias AccessToken = KitsuModels.Token
}

public extension DependencyValues {
    var kitsuClient: KitsuClient {
        get { self[KitsuClient.self] }
        set { self[KitsuClient.self] = newValue }
    }
}

extension KitsuClient.AccessToken {
    var isValid: Bool {
        created_at.advanced(by: .init(expires_in)) > .init()
    }
}

// MARK: - KitsuClient + DependencyKey

extension KitsuClient: DependencyKey {
    private final actor Session: @unchecked
    Sendable {
        let accessToken = AsyncLock<AccessToken?>(nil)
        let user = AsyncLock<User?>(nil)
        let userCollections = AsyncLock<Collections?>(nil)

        private static let accessTokenFile = "kitsu-access-token"

        @Dependency(\.apiClient)
        private var apiClient

        @Dependency(\.authenticationClient)
        private var authenticationClient

        @Dependency(\.fileClient)
        private var fileClient

        func initialize() async throws {
            let accessToken = try await fileClient.load(AccessToken.self, from: Self.accessTokenFile)
            await self.accessToken.setValue(accessToken)
            _ = try await getUser(refresh: true)
        }

        func logIn() async throws -> User {
            enum KitsuLogInError: Error {
                case malformedPassword
            }

            let token = try await authenticationClient.logIn(
                title: "Kitsu",
                image: "kitsu_logo",
                description: "Log in with your Kitsu credentials!"
            ) { [unowned self] userInfo in
                guard let password = userInfo.password
                    .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowedRFC3986) else {
                    throw KitsuLogInError.malformedPassword
                }
                return try await apiClient.request(
                    .kitsu(
                        .createToken(
                            userInfo.username,
                            password
                        )
                    )
                )
            }

            try await updateAccessToken(token)
            return try await getUser(refresh: true)
        }

        func logOut() async {
            await user.setValue(nil)
            await userCollections.setValue(nil)
            try? await updateAccessToken(nil)
        }

        func getUser(refresh: Bool = false) async throws -> User {
            try await user.withValue { user in
                if !refresh, let user {
                    return user
                } else {
                    let newUser = try await tokenRequired { token in
                        try await apiClient.request(
                            .kitsu(
                                .graphql(
                                    KitsuModels.CurrentAccountQuery.self,
                                    .init(),
                                    token.access_token
                                )
                            )
                        )
                        .data
                        .currentAccount
                        .profile
                    }
                    user = newUser
                    return newUser
                }
            }
        }

        func userCollections(refresh: Bool = false) async throws -> Collections {
            if !refresh, let userCollections = await userCollections.value {
                return userCollections
            } else {
                let library = try await tokenRequired { [unowned self] token in
                    try await apiClient.request(
                        .kitsu(
                            .graphql(
                                KitsuModels.CurrentAccountQuery.self,
                                .init(
                                    arguments: .init(
                                        profileArguments: .init(
                                            libraryArguments: .init()
                                        )
                                    )
                                ),
                                token.access_token
                            )
                        )
                    )
                }
                .data
                .currentAccount
                .profile
                .library

                await userCollections.setValue(library)

                guard let library else {
                    throw URLError(.resourceUnavailable)
                }
                return library
            }
        }

        func sync(_ animeId: String, _ progress: Int?) async throws {
            try await tokenRequired { [unowned self] token in
                if let progress {
                    let inLibrary = try? await apiClient.request(
                        .kitsu(
                            .graphql(
                                KitsuModels.LibraryEntryUpdateProgressByMediaMutation.self,
                                .init(
                                    mediaId: animeId,
                                    mediaType: .ANIME,
                                    progress: progress
                                ),
                                token.access_token
                            )
                        )
                    )

                    if inLibrary == nil {
                        try await apiClient.request(
                            .kitsu(
                                .graphql(
                                    KitsuModels.LibraryEntryCreateMutation.self,
                                    .init(mediaId: animeId, progress: progress),
                                    token.access_token
                                )
                            )
                        )
                    }
                } else {
                    let inLibrary = try? await apiClient.request(
                        .kitsu(
                            .graphql(
                                KitsuModels.LibraryEntryUpdateStatusByMediaMutation.self,
                                .init(
                                    mediaId: animeId,
                                    mediaType: .ANIME,
                                    status: .CURRENT
                                ),
                                token.access_token
                            )
                        )
                    )

                    if inLibrary == nil {
                        try await apiClient.request(
                            .kitsu(
                                .graphql(
                                    KitsuModels.LibraryEntryCreateMutation.self,
                                    .init(mediaId: animeId),
                                    token.access_token
                                )
                            )
                        )
                    }
                }
            }
        }

        private func tokenRequired<O>(_ operation: (AccessToken) async throws -> O) async throws -> O {
            guard let token = await accessToken.value else {
                throw URLError(.userAuthenticationRequired)
            }

            if token.isValid {
                return try await operation(token)
            } else {
                let newToken = try await apiClient.request(
                    .kitsu(.refreshToken(token.refresh_token))
                )
                try await updateAccessToken(newToken)
                return try await operation(newToken)
            }
        }

        private func updateAccessToken(_ accessToken: AccessToken?) async throws {
            if let accessToken {
                try await fileClient.save(accessToken, to: Self.accessTokenFile)
            } else {
                try await fileClient.delete(Self.accessTokenFile)
            }
            await self.accessToken.setValue(accessToken)
        }
    }

    public static let liveValue: KitsuClient = {
        let session = Session()

        return .init(
            initialize: { try await session.initialize() },
            logIn: { try await session.logIn() },
            logOut: { await session.logOut() },
            loggedIn: { await session.accessToken.value != nil },
            refreshUser: { try await session.getUser(refresh: true) },
            user: { await session.user.value },
            userCollections: { try await session.userCollections() },
            sync: { try await session.sync($0, $1) }
        )
    }()
}

private extension CharacterSet {
    static var urlQueryAllowedRFC3986: CharacterSet {
        var alphanums = alphanumerics
        alphanums.insert(charactersIn: "-._~")
        return alphanums
    }
}

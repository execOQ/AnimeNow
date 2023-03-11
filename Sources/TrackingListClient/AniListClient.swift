//
//  AniListClient.swift
//
//
//  Created by ErrorErrorError on 2/25/23.
//
//

import APIClient
import AuthenticationClient
import ComposableArchitecture
import FileClient
import Foundation
import Utilities

// MARK: - AniListClient

public struct AniListClient: TrackableList {
    public var name: String { "AniList" }
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
    public let sync: @Sendable (Int, Int?) async throws -> Void
}

public extension AniListClient {
    typealias User = AniListModels.User
    typealias Collections = AniListModels.MediaListCollection

    fileprivate struct AccessToken: Equatable, Codable {
        let token: String
        let expires: Date
    }
}

// MARK: DependencyKey

extension AniListClient: DependencyKey {
    final actor Session: @unchecked
    Sendable {
        fileprivate let accessToken = AsyncLock<AccessToken?>(nil)
        fileprivate let currentUser = AsyncLock<User?>(nil)
        fileprivate let userCollections = AsyncLock<Collections?>(nil)

        private static let accessTokenFile = "anilist-access-token"

        @Dependency(\.fileClient)
        private var fileClient

        @Dependency(\.authenticationClient)
        private var authenticationClient

        @Dependency(\.apiClient)
        private var apiClient

        init() {}

        func initialize() async throws {
            let accessToken = try await fileClient.load(AccessToken.self, from: Self.accessTokenFile)
            await self.accessToken.setValue(accessToken)
            _ = try await refreshUser()
        }

        func logIn() async throws -> User {
            var components = URLComponents()
            components.scheme = "https"
            components.host = "anilist.co"
            components.path = "/api/v2/oauth/authorize"
            components.queryItems = .init([
                "client_id": 11_352,
                "response_type": "token"
            ])

            let loginURL = components.url.unsafelyUnwrapped

            let url = try await authenticationClient.authenticate(loginURL)

            var urlComponents = URLComponents()
            urlComponents.query = url.fragment

            guard let token = urlComponents.queryItems?.first(where: { $0.name == "access_token" })?.value,
                  let expirationString = urlComponents.queryItems?.first(where: { $0.name == "expires_in" })?.value,
                  let expiration = Double(expirationString)
            else {
                throw URLError(.badServerResponse)
            }

            let time = Date().advanced(by: expiration)

            let accessToken = AccessToken(token: token, expires: time)
            try await updateAccessToken(accessToken)

            return try await refreshUser()
        }

        func logOut() async {
            await currentUser.setValue(nil)
            await userCollections.setValue(nil)
            try? await updateAccessToken(nil)
        }

        func refreshUser() async throws -> User {
            let user = try await tokenRequired { [unowned self] accessToken in
                try await apiClient.request(
                    .anilist(
                        .graphql(AniListModels.Viewer.self, accessToken.token)
                    )
                )
                .data
                .Viewer
            }
            await currentUser.setValue(user)
            return user
        }

        func userCollections(refresh: Bool = false) async throws -> AniListModels.MediaListCollection {
            if !refresh, let userCollections = await userCollections.value {
                return userCollections
            } else {
                let collections = try await userRequired { [unowned self] user in
                    try await apiClient.request(
                        .anilist(
                            .graphql(
                                AniListModels.MediaListCollectionQuery.self,
                                .init(userId: user.id)
                            )
                        )
                    )
                    .data
                    .MediaListCollection
                }
                await userCollections.setValue(collections)
                return collections
            }
        }

        func sync(_ animeId: Int, _ episodeNumber: Int?) async throws {
            try await tokenRequired { [unowned self] accessToken in
                try await apiClient.request(
                    .anilist(
                        .graphql(
                            AniListModels.SaveMediaListEntryMutation.self,
                            .init(
                                mediaId: animeId,
                                status: episodeNumber == nil ? .CURRENT : nil,
                                progress: episodeNumber
                            ),
                            accessToken.token
                        )
                    )
                )
            }
        }

        @discardableResult
        private func userRequired<O>(_ operation: @escaping @Sendable (User) async throws -> O) async throws -> O {
            if let currentUser = await currentUser.value {
                return try await operation(currentUser)
            } else {
                return try await operation(try await refreshUser())
            }
        }

        @discardableResult
        private func tokenRequired<O>(_ operation: @escaping @Sendable (AccessToken) async throws -> O) async throws -> O {
            guard let token = await accessToken.value else {
                throw URLError(.userAuthenticationRequired)
            }

            return try await operation(token)
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

    public static let liveValue: Self = {
        let session = Session()

        return Self(
            initialize: { try await session.initialize() },
            logIn: { try await session.logIn() },
            logOut: { await session.logOut() },
            loggedIn: { await session.accessToken.value != nil },
            refreshUser: { try await session.refreshUser() },
            user: { await session.currentUser.value },
            userCollections: { try await session.userCollections() },
            sync: { try await session.sync($0, $1) }
        )
    }()
}

public extension DependencyValues {
    var anilistClient: AniListClient {
        get { self[AniListClient.self] }
        set { self[AniListClient.self] = newValue }
    }
}

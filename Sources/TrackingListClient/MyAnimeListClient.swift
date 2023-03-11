//
//  MyAnimeListReducer.swift
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

// MARK: - MyAnimeListClient

public struct MyAnimeListClient: TrackableList {
    public var name: String { "MyAnimeList" }
    public let initialize: @Sendable () async throws -> Void
    public let logIn: @Sendable () async throws -> User
    public let logOut: @Sendable ()
        async -> Void
    public let loggedIn: @Sendable ()
        async -> Bool
    public let refreshUser: @Sendable () async throws -> User
    public let user: @Sendable ()
        async -> User?
    public let userCollections: @Sendable () async throws -> MyAnimeListClient.Collections
    public let sync: @Sendable (Int, Int?) async throws -> Void
}

public extension MyAnimeListClient {
    typealias User = MalModels.UserInfo
    typealias Collections = [ListGroup]

    fileprivate struct AccessToken: Codable, Equatable {
        let token: String
        let refreshToken: String
        let expires: Date

        var isValid: Bool {
            expires > .init()
        }
    }

    fileprivate enum AuthError: Error {
        case failedToRetrieveCode
        case failedToRetrieveToken
    }

    struct ListGroup: Equatable {
        public let status: MalModels.Status
        public let items: [MalModels.AnimeList]
    }
}

public extension DependencyValues {
    var myanimelistClient: MyAnimeListClient {
        get { self[MyAnimeListClient.self] }
        set { self[MyAnimeListClient.self] = newValue }
    }
}

// MARK: - MyAnimeListClient + DependencyKey

extension MyAnimeListClient: DependencyKey {
    private actor Session: @unchecked
    Sendable {
        private static let accessTokenFile = "mal-access-token"
        private static let clientId = "49177d714632ab989bd48b6cd99b1d6f"

        let accessToken = AsyncLock<AccessToken?>(nil)
        let user = AsyncLock<User?>(nil)
        let userCollection = AsyncLock<Collections?>(nil)

        @Dependency(\.apiClient)
        private var apiClient

        @Dependency(\.authenticationClient)
        private var authenticationClient

        @Dependency(\.fileClient)
        private var fileClient

        func initialize() async throws {
            try await accessToken.withValue { token in
                token = try await fileClient.load(AccessToken.self, from: Self.accessTokenFile)
            }
            _ = try await refreshUser()
        }

        func logIn() async throws -> User {
            var buffer = Data(count: 32)
            _ = buffer.withUnsafeMutableBytes { pointer in
                SecRandomCopyBytes(
                    kSecRandomDefault,
                    pointer.count,
                    pointer.baseAddress.unsafelyUnwrapped
                )
            }

            let codeVerifier = buffer.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: ".")

            var components = URLComponents()
            components.scheme = "https"
            components.host = "myanimelist.net"
            components.path = "/v1/oauth2/authorize"
            components.queryItems = .init([
                "response_type": "code",
                "client_id": Self.clientId,
                "code_challenge": codeVerifier
            ])

            let loginURL = components.url.unsafelyUnwrapped

            // Verify URL

            let url = try await authenticationClient.authenticate(loginURL)

            var urlComponents = URLComponents()
            urlComponents.query = url.query

            guard let code = urlComponents.queryItems?.first(where: { $0.name == "code" })?.value else {
                throw AuthError.failedToRetrieveCode
            }

            let accessInfo = try await apiClient.request(
                .mal(
                    .retrieveToken(
                        clientId: Self.clientId,
                        code: code,
                        codeVerifier: codeVerifier
                    )
                )
            )

            let accessToken = AccessToken(
                token: accessInfo.access_token,
                refreshToken: accessInfo.refresh_token,
                expires: .init().advanced(by: .init(accessInfo.expires_in))
            )
            try await updateAccessToken(accessToken)
            return try await refreshUser()
        }

        func logOut() async {
            await user.setValue(nil)
            await userCollection.setValue(nil)
            try? await updateAccessToken(nil)
        }

        func refreshUser() async throws -> User {
            try await tokenRequired { [unowned self] accessToken in
                let user = try await apiClient.request(.mal(.getUserInfo(token: accessToken.token)))
                await self.user.setValue(user)
                return user
            }
        }

        func userCollections(refresh: Bool = false) async throws -> MyAnimeListClient.Collections {
            if !refresh, let userCollection = await userCollection.value {
                return userCollection
            } else {
                let collection = try await tokenRequired { [unowned self] token in
                    Dictionary(
                        grouping: try await apiClient.request(
                            .mal(.getUserAnimeList(accessToken: token.token))
                        )
                        .data,
                        by: \.list_status.status
                    )
                    .compactMap { (key: MalModels.Status?, value: [MalModels.AnimeList]) in
                        key.flatMap { ListGroup(status: $0, items: value) }
                    }
                }

                await userCollection.setValue(collection)
                return collection
            }
        }

        func sync(_ id: Int, _ episodeNumber: Int?) async throws {
            try await tokenRequired { [unowned self] accessToken in
                try await apiClient.request(
                    .mal(
                        .updateListItem(
                            accessToken: accessToken.token,
                            .init(
                                mediaId: id,
                                status: episodeNumber == nil ? .watching : nil,
                                numWatchedEpisodes: episodeNumber
                            )
                        )
                    )
                )
            }
        }

        @discardableResult
        private func tokenRequired<O>(
            _ operation: @escaping (AccessToken) async throws -> O
        ) async throws -> O {
            guard let token = await accessToken.value else {
                throw URLError(.userAuthenticationRequired)
            }

            if token.isValid {
                return try await operation(token)
            } else {
                let newToken = try await apiClient.request(
                    .mal(
                        .refreshToken(
                            clientId: Self.clientId,
                            accessToken: token.token,
                            refreshToken: token.refreshToken
                        )
                    )
                )
                let updatedAccessToken = AccessToken(
                    token: newToken.access_token,
                    refreshToken: newToken.refresh_token,
                    expires: .init().advanced(by: .init(newToken.expires_in))
                )
                try await updateAccessToken(updatedAccessToken)
                return try await operation(updatedAccessToken)
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

    public static let liveValue: MyAnimeListClient = {
        let session = Session()

        return .init(
            initialize: { try await session.initialize() },
            logIn: { try await session.logIn() },
            logOut: { await session.logOut() },
            loggedIn: { await session.accessToken.value != nil },
            refreshUser: { try await session.refreshUser() },
            user: { await session.user.value },
            userCollections: { try await session.userCollections() },
            sync: { try await session.sync($0, $1) }
        )
    }()
}

// MARK: - MyAnimeListClient.User + Equatable

extension MyAnimeListClient.User: Equatable {
    public static func == (
        lhs: MalModels.UserInfo,
        rhs: MalModels.UserInfo
    ) -> Bool {
        lhs.id == rhs.id &&
            lhs.name == rhs.name &&
            lhs.picture == rhs.picture
    }
}

//
//  File.swift
//
//
//  Created by ErrorErrorError on 2/26/23.
//
//

import Foundation

// MARK: - TrackingListClient.AuthState

public extension TrackingListClient {
    enum AuthState: Equatable {
        case unauthenticated
        case authenticated
        case expired

        public var isAuthenticated: Bool {
            self != .unauthenticated
        }
    }
}

// MARK: - TrackableList

public protocol TrackableList {
    associatedtype MediaID
    associatedtype User: Equatable
    associatedtype Collections
    var name: String { get }
    var initialize: @Sendable () async throws -> Void { get }
    var logIn: @Sendable () async throws -> User { get }
    var logOut: @Sendable ()
        async -> Void { get }
    var loggedIn: @Sendable ()
        async -> Bool { get }
    var refreshUser: @Sendable () async throws -> User { get }
    var user: @Sendable ()
        async -> User? { get }
    var userCollections: @Sendable () async throws -> Collections { get }
    var sync: @Sendable (MediaID, Int?) async throws -> Void { get }
}

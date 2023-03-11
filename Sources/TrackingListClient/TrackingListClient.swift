//
//  TrackingListClient.swift
//
//
//  Created by ErrorErrorError on 2/16/23.
//
//

import APIClient
import ComposableArchitecture
import Foundation
import Utilities

// MARK: - TrackingListClient

public struct TrackingListClient {
    public let sync: (Int, Int?) async throws -> Void
}

// MARK: DependencyKey

extension TrackingListClient: DependencyKey {}

public extension DependencyValues {
    var trackingListClient: TrackingListClient {
        get { self[TrackingListClient.self] }
        set { self[TrackingListClient.self] = newValue }
    }
}

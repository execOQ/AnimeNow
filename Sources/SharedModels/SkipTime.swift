//
//  SkipTime.swift
//  Anime Now!
//
//  Created by ErrorErrorError on 10/11/22.
//

import Foundation

public struct SkipTime: Hashable {
    public let startTime: Double // 0...1
    public let endTime: Double // 0...1
    public let type: Option

    public init(
        startTime: Double,
        endTime: Double,
        type: SkipTime.Option
    ) {
        self.startTime = startTime
        self.endTime = endTime
        self.type = type
    }

    public enum Option: Hashable {
        case recap
        case opening
        case ending
        case mixedOpening
        case mixedEnding
    }

    public func isInRange(_ progress: Double) -> Bool {
        startTime <= progress && progress < endTime
    }

    public var duration: Double {
        endTime - startTime
    }
}

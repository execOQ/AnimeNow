//
//  File.swift
//
//
//  Created by ErrorErrorError on 3/11/23.
//
// Modified version of https://github.com/groue/Semaphore

import Foundation

// MARK: - Suspension

private class Suspension {
    enum State {
        /// Initial state. Next is suspended, or cancelled.
        case pending

        /// Waiting for a signal, with support for cancellation.
        case suspendedUnlessCancelled(UnsafeContinuation<Void, Error>)

        /// Waiting for a signal, with no support for cancellation.
        case suspended(UnsafeContinuation<Void, Never>)

        /// Cancelled before we have started waiting.
        case cancelled
    }

    var state: State

    init() {
        self.state = .pending
    }

    init(continuation: UnsafeContinuation<Void, Never>) {
        self.state = .suspended(continuation)
    }
}

// MARK: - AsyncLock

public final class AsyncLock<Value>: @unchecked Sendable {
    public var value: Value {
        get async {
            await wait()
            defer { signal() }
            return _value
        }
    }

    private var _value: Value
    private let _lock: NSRecursiveLock
    private var _allowedCalls = 1
    private var suspensions: [Suspension] = []

    public init(_ value: Value) {
        self._value = value
        self._lock = .init()
    }

    public func setValue(_ value: @autoclosure @Sendable () -> Value) async {
        await wait()
        defer { signal() }
        _value = value()
    }

    public func withValue<Output>(_ work: (inout Value) async throws -> Output) async rethrows -> Output {
        await wait()
        defer { signal() }
        var value = _value
        defer { self._value = value }
        return try await work(&value)
    }

    func wait() async {
        lock()
        _allowedCalls -= 1

        if _allowedCalls >= 0 {
            unlock()
            return
        }

        await withUnsafeContinuation { continuation in
            suspensions.insert(Suspension(continuation: continuation), at: 0)
            unlock()
        }
    }

    func lock() { _lock.lock() }
    func unlock() { _lock.unlock() }

    @discardableResult
    func signal() -> Bool {
        lock()
        defer { unlock() }

        _allowedCalls += 1

        switch suspensions.popLast()?.state {
        case let .suspendedUnlessCancelled(continuation):
            continuation.resume()
            return true
        case let .suspended(continuation):
            continuation.resume()
            return true
        default:
            return false
        }
    }
}

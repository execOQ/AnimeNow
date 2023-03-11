//
//  APIClient+Live.swift
//
//
//  Created by ErrorErrorError on 12/27/22.
//
//

import Build
import ComposableArchitecture
import Foundation
import Logger

// MARK: - APIClientLive

public final class APIClientLive: APIClient {
    public func request<O>(_ request: Request<O>) async throws -> O where O: Decodable {
        do {
            var urlRequest = try request.makeRequest()
            urlRequest.setHeaders()
            let (data, _) = try await URLSession.shared.data(for: urlRequest)
            return try request.decoder.decode(O.self, from: data)
        } catch {
            Logger.log(
                .error,
                "\(request) failed with error: \(error)"
            )
            throw error
        }
    }
}

// MARK: - Request + CustomStringConvertible

extension Request: CustomStringConvertible {
    public var description: String {
        """
        Request(
            base: \(base),
            path: \(path),
            query: \(query ?? []),
            method: \(method),
            headers: \(headers?.mapValues { $0.description.localizedCaseInsensitiveContains("Bearer") ? "***" : $0 } ?? [:])
        )
        """
    }

    func makeRequest() throws -> URLRequest {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: true) else {
            throw URLError(.badURL)
        }

        components.path += path.isEmpty ? "" : "/" + path.map(\.description).joined(separator: "/")
        components.queryItems = query

        guard let url = components.url else {
            throw URLError(.unsupportedURL)
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method.stringValue

        if case let .post(data) = method {
            urlRequest.httpBody = data
        } else if case let .put(data) = method {
            urlRequest.httpBody = data
        }

        headers?.forEach { key, value in
            urlRequest.setValue(value.description, forHTTPHeaderField: key)
        }
        return urlRequest
    }
}

private extension URLRequest {
    mutating func setHeaders() {
        @Dependency(\.build)
        var build
        let info = Bundle.main.infoDictionary
        let executable = info?[kCFBundleNameKey as String] ?? "Anime Now!"
        let bundle = info?[kCFBundleIdentifierKey as String] ?? "Unknown"
        let appVersion = build.version()
        let appCommit = build.gitSha()
        let osVersion = {
            let version = ProcessInfo.processInfo.operatingSystemVersion
            return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        }()
        let osName = {
            #if os(iOS)
            #if targetEnvironment(macCatalyst)
            return "macOS(Catalyst)"
            #else
            return "iOS"
            #endif
            #elseif os(watchOS)
            return "watchOS"
            #elseif os(tvOS)
            return "tvOS"
            #elseif os(macOS)
            return "macOS"
            #else
            return "Unknown"
            #endif
        }()

        setValue(
            "\(executable)/\(appVersion) (\(bundle); commit:\(appCommit)) \(osName) \(osVersion)",
            forHTTPHeaderField: "User-Agent"
        )
    }
}

extension URLSession {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if #available(iOS 15, macOS 12.0, *) {
            return try await self.data(for: request, delegate: nil)
        } else {
            return try await withCheckedThrowingContinuation { continuation in
                let task = self.dataTask(with: request) { data, response, error in
                    guard let data, let response else {
                        let error = error ?? URLError(.badServerResponse)
                        return continuation.resume(throwing: error)
                    }

                    continuation.resume(returning: (data, response))
                }

                task.resume()
            }
        }
    }

    func data(from url: URL) async throws -> (Data, URLResponse) {
        if #available(iOS 15, macOS 12.0, *) {
            return try await self.data(from: url, delegate: nil)
        } else {
            return try await withCheckedThrowingContinuation { continuation in
                let task = self.dataTask(with: url) { data, response, error in
                    guard let data, let response else {
                        let error = error ?? URLError(.badServerResponse)
                        return continuation.resume(throwing: error)
                    }

                    continuation.resume(returning: (data, response))
                }

                task.resume()
            }
        }
    }
}

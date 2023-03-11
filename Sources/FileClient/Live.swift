//
//  Live.swift
//
//
//  Created by ErrorErrorError on 1/16/23.
//
//

import ComposableArchitecture
import Foundation

// MARK: - FileClient + DependencyKey

extension FileClient: DependencyKey {
    private actor Manager {
        let manager: FileManager

        init() {
            self.manager = FileManager.default
        }

        func load(_ directory: URL, _ fileName: String) throws -> Data {
            try Data(
                contentsOf: directory
                    .appendingPathComponent(fileName)
                    .appendingPathExtension("json")
            )
        }

        func save(_ directory: URL, _ fileName: String, _ data: Data) throws {
            try data.write(
                to: directory
                    .appendingPathComponent(fileName)
                    .appendingPathExtension("json")
            )
        }

        func delete(_ directory: URL, _ fileName: String) throws {
            try FileManager.default.removeItem(
                at: directory
                    .appendingPathComponent(fileName)
                    .appendingPathExtension("json")
            )
        }
    }

    public static let liveValue = {
        let manager = Manager()

        let mainDirectory = Self.applicationDirectory

        if !FileManager.default.fileExists(atPath: mainDirectory.path) {
            do {
                try FileManager.default.createDirectory(
                    at: mainDirectory,
                    withIntermediateDirectories: true
                )
            } catch {
                print("Failed to create main directory: \(error)")
            }
        }

        return Self(
            delete: { name in
                try await manager.delete(mainDirectory, name)
            },
            load: { name in
                try await manager.load(mainDirectory, name)
            },
            save: { name, data in
                try await manager.save(mainDirectory, name, data)
            }
        )
    }()
}

public extension FileClient {
    static let applicationDirectory = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(
            Bundle.main.bundleIdentifier ?? "com.errorerrorerror.animenow",
            isDirectory: true
        )
}

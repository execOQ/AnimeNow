//
//  Models.swift
//  Anime Now! (iOS)
//
//  Created by ErrorErrorError on 9/6/22.
//

import Foundation
import SociableWeaver

// MARK: - GraphQLArgument

public protocol GraphQLArgument {
    func getValue() -> ArgumentValueRepresentable
    var description: String { get }
}

// MARK: - GraphQLQueryObject

public protocol GraphQLQueryObject: Decodable {
    associatedtype Argument
    static func createQueryObject(_ name: String, _ arguments: Argument) -> Object
}

public extension GraphQLQueryObject {
    static func createQueryObject(_ name: CodingKey, _ arguments: Argument) -> Object {
        createQueryObject(name.stringValue, arguments)
    }

    static func createQueryObject(_ name: CodingKey) -> Object where Argument == Void {
        createQueryObject(name.stringValue, ())
    }

    static func createQueryObject(_ name: String) -> Object where Argument == Void {
        createQueryObject(name, ())
    }
}

// MARK: - GraphQLQuery

public protocol GraphQLQuery: Decodable {
    associatedtype QueryOptions
    associatedtype Response: Decodable
    static func createQuery(_ options: QueryOptions) -> Weave
}

// MARK: - GraphQL

public enum GraphQL {
    public struct Paylod: Codable, Equatable {
        let query: String
        var operationName: String?
        var variables: [String: String] = [:]

        public init(
            query: String,
            operationName: String? = nil,
            variables: [String: String] = [:]
        ) {
            self.query = query
            self.operationName = operationName
            self.variables = variables
        }
    }

    public struct Response<T: Decodable>: Decodable {
        public let data: T
    }

    public struct NodeList<T: Decodable, P: Decodable>: Decodable {
        public let nodes: [T]
        public let pageInfo: P
    }
}

// MARK: - DefaultArguments

public protocol DefaultArguments {
    static var defaultArgs: [Self] { get }
}

public extension Collection where Element: DefaultArguments {
    static var defaultArgs: [Element] { Element.defaultArgs }
}

public extension Object {
    func argument(_ argument: some GraphQLArgument) -> Self {
        let argumentKey = argument.description
        let value = argument.getValue()
        return self.argument(key: argumentKey, value: value)
    }

    init(name: String, @WeavableBuilder builder: () -> ObjectWeavable) {
        self.init(name) { builder() }
    }

    init(name: CodingKey, @WeavableBuilder builder: () -> ObjectWeavable) {
        self.init(name: name.stringValue) { builder() }
    }
}

// MARK: - WeavableBuilder

@resultBuilder
enum WeavableBuilder {
    static func buildBlock(_ components: ObjectWeavable...) -> ObjectWeavable {
        GroupWeave(items: components)
    }

    static func buildEither(first component: ObjectWeavable) -> ObjectWeavable {
        component
    }

    static func buildEither(second component: ObjectWeavable) -> ObjectWeavable {
        component
    }

    static func buildArray(_ components: [ObjectWeavable]) -> ObjectWeavable {
        GroupWeave(items: components)
    }

    static func buildOptional(_ component: ObjectWeavable?) -> ObjectWeavable {
        component ?? EmptyWeave()
    }
}

// MARK: - GroupWeave

struct GroupWeave: ObjectWeavable {
    var items: [ObjectWeavable]
    var description: String {
        let val = items
            .map(\.description)
            .joined(separator: " ")
        return val
    }

    var debugDescription: String { description }
}

// MARK: - EmptyWeave

struct EmptyWeave: ObjectWeavable {
    var description: String = ""
    var debugDescription: String = ""
}

public extension Field {
    func argument(_ argument: some GraphQLArgument) -> Self {
        let argumentKey = argument.description
        let value = argument.getValue()
        return self.argument(key: argumentKey, value: value)
    }
}

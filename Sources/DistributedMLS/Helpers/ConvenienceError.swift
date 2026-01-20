//
//  ConvenienceError.swift
//  DiMLS
//
//  Created by Mark @ Germ on 1/13/26.
//

import Foundation

extension Optional {
    public var tryUnwrap: Wrapped {
        get throws {
            guard let self else {
                throw ConvenienceError.missingOptional("\(Wrapped.self)")
            }
            return self
        }
    }

    public func tryUnwrap(_ error: Error) throws -> Wrapped {
        guard let self else { throw error }
        return self
    }
}

extension Array {
    public var expectOne: Element {
        get throws {
            switch count {
            case 0: throw ConvenienceError.emptyArray
            case 1: try first.tryUnwrap
            default: throw ConvenienceError.tooManyElements
            }
        }
    }
}

enum ConvenienceError: Error {
    case missingOptional(String)
    case emptyArray
    case tooManyElements
}

extension ConvenienceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingOptional(let type): "Expected to find an optional \(type), but didn't."
        case .emptyArray: "Expected to find a value in an array, but the array was empty."
        case .tooManyElements:
            "Expected to find a single value in an array, but the array had multiple values."
        }
    }
}

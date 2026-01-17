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

enum ConvenienceError: Error {
    case missingOptional(String)
}

extension ConvenienceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingOptional(let type): "Expected to find an optional \(type), but didn't."
        }
    }
}

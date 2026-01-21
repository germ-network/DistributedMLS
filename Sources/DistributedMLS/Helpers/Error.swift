//
//  Error.swift
//  DiMLS
//
//  Created by Mark @ Germ on 1/4/26.
//

import Foundation

public enum DiMLSError: Error {
    case missingRemoteState
    case mismatchedGroupId
    case duplicateSendGroup
    case notImplemented
    case disallowed
    case sendGroupNotReady
    case duplicateMember
    case decryptFallthrough
    case expecting(DiMLS.Dependency)
}

extension DiMLSError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingRemoteState: "Missing remote state"
        case .mismatchedGroupId: "Mismatched group ID"
        case .duplicateSendGroup: "Duplicate send group"
        case .notImplemented: "Not implemented"
        case .disallowed: "Disallowed"
        case .sendGroupNotReady: "Send group not ready"
        case .duplicateMember: "Duplicate member"
        case .decryptFallthrough: "Decryption fallthrough"
        case .expecting: "Missing dependency"
        }
    }
}

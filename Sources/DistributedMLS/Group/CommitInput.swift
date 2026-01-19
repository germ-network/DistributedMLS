//
//  CommitInput.swift
//  DiMLS
//
//  Created by Mark @ Germ on 1/11/26.
//

import Foundation

extension DiMLS {
    public struct CommitInput<C: DiMLSCredential> {
        public var localOps: Set<DiMLSOperations<C>>
        public var followOps: Set<DiMLSOperations<C>>

        var dependencies: [Dependency]

        public var newSenderLeafNode: Bool

        public init() {
            localOps = []
            followOps = []
            dependencies = []
            newSenderLeafNode = false
        }
    }

    //psk's
    public struct Dependency: Codable, Sendable, Hashable {
        public let pskSource: ReferenceID
        public let epoch: EpochID

        public init(pskSource: ReferenceID, epoch: EpochID) {
            self.pskSource = pskSource
            self.epoch = epoch
        }
    }

    public struct KeyedDependency: Codable, Sendable {
        public let dependency: Dependency
        public let keyData: Data

        public init(dependency: Dependency, keyData: Data) {
            self.dependency = dependency
            self.keyData = keyData
        }
    }
}

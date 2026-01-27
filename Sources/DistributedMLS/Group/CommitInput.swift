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
        public var followOps: [PendingState<C>.FollowOp]

        public var dependencies: [KeyedDependency]

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

extension DiMLS {
    //lookup table that we pass from total group to a client to process
    public typealias AvailableDependendencies = [ReferenceID: [EpochID: KeyedDependency]]
}
extension DiMLS.TotalGroup {
    public var keyedDependencies: DiMLS.AvailableDependendencies {
        members.compactMapValues {
            guard case .claimed(let epochs) = $0 else {
                return nil
            }
            return epochs.reduce(into: [:]) { result, epoch in
                if let keyedDependency = epoch.keyedDependency {
                    result[epoch.epoch] = keyedDependency
                }
            }
        }
    }
}

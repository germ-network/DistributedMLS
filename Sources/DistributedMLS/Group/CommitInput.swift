//
//  CommitInput.swift
//  DiMLS
//
//  Created by Mark @ Germ on 1/11/26.
//

extension DiMLS {
    public struct CommitInput<C: DiMLSCredential> {
        public var proposals: Set<DiMLSOperations<C>>

        //psk's
        struct Dependency {
            let pskSource: ReferenceID
            let epoch: EpochID
        }
        var dependencies: [Dependency]

        public var newSenderLeafNode: Bool

        public init() {
            proposals = []
            dependencies = []
            newSenderLeafNode = false
        }

        private init(
            proposals: [DiMLSOperations<C>],
            dependencies: [Dependency],
            newSenderLeafNode: Bool
        ) {
            self.proposals = .init(proposals)
            self.dependencies = dependencies
            self.newSenderLeafNode = newSenderLeafNode
        }
    }
}

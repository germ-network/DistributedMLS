//
//  PendingState.swift
//  DiMLS
//
//  Created by Mark @ Germ on 1/10/26.
//

import os

extension DiMLS {
    public final class PendingState<C: DiMLSCredential> {
        var applicationRequestsNewKeyDistribution: Bool
        public var localOps: Set<DiMLSOperations<C>>
        //this includes incorporating PCS updates
        var followOps: [FollowOp]

        public static func create() -> Self {
            .init(
                applicationRequestsNewKeyDistribution: false,
                localOps: [],
                followOps: []
            )
        }

        init(
            applicationRequestsNewKeyDistribution: Bool,
            localOps: Set<DiMLSOperations<C>>,
            followOps: [FollowOp]
        ) {
            self.applicationRequestsNewKeyDistribution = applicationRequestsNewKeyDistribution
            self.localOps = localOps
            self.followOps = followOps
        }

        //MARK: Archive
        public struct Archive: Sendable, Codable {
            let applicationRequestsNewKeyDistribution: Bool
            let localOps: [DiMLSOperations<C>.Archive]
            //this includes incorporating PCS updates
            let followOps: [FollowOp.Archive]
        }

        public init(archive: Archive) throws {
            self.applicationRequestsNewKeyDistribution =
                archive.applicationRequestsNewKeyDistribution
            self.localOps = try .init(
                archive.localOps.map {
                    try .init(archive: $0)
                })
            self.followOps = try archive.followOps
                .map { try .init(archive: $0) }
        }

        public var archive: Archive {
            get throws {
                .init(
                    applicationRequestsNewKeyDistribution: applicationRequestsNewKeyDistribution,
                    localOps: try localOps.map { try $0.archive },
                    followOps:
                        try followOps
                        .map { try $0.archive },
                )
            }
        }

        public var commitNeeded: Bool {
            applicationRequestsNewKeyDistribution || !localOps.isEmpty
                || !followOps.isEmpty
        }

        public func stageAdd(member: DiMLS.CredentialedKeyPackage<C>) throws {
            localOps.insert(.add(member))
        }

        public func prepareCommit() throws -> DiMLS.CommitInput<C> {
            assert(commitNeeded)
            var result = DiMLS.CommitInput<C>()
            //first follow remote ops
            //TODO

            //then perform own actions if not redundant
            for action in localOps {
                result.localOps.insert(action)
            }

            //inject causal dependency if needed
            //TODO

            //broadcast new keys if necessary
            //TODO

            return result
        }

        func committed(input: CommitInput<C>) {
            for localOp in input.localOps {
                localOps.remove(localOp)
            }
        }

        public func accumulateAdds() throws -> DiMLS.CommitInput<C>? {
            //currently the same
            if commitNeeded {
                try prepareCommit()
            } else {
                nil
            }
        }
    }
}

extension DiMLS.PendingState {
    public struct FollowOp {
        let operation: DiMLSOperations<C>
        let dependency: DiMLS.KeyedDependency?
    }
}

extension DiMLS.PendingState.FollowOp: Archivable {
    public struct Archive: Codable, Sendable {
        let operation: DiMLSOperations<C>.Archive
        let dependency: DiMLS.KeyedDependency?
    }

    public init(archive: Archive) throws {
        self.init(
            operation: try .init(archive: archive.operation),
            dependency: archive.dependency
        )
    }

    var archive: Archive {
        get throws {
            try .init(operation: try operation.archive, dependency: dependency)
        }
    }
}

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
        public var pendingLocalOps: Set<DiMLSOperations<C>>
        //this includes incorporating PCS updates
        var pendingFollowOps: [DiMLS.ReferenceID: DiMLSOperations<C>]

        public static func create() -> Self {
            .init(
                applicationRequestsNewKeyDistribution: false,
                pendingLocalOps: [],
                pendingFollowOps: [:]
            )
        }

        init(
            applicationRequestsNewKeyDistribution: Bool,
            pendingLocalOps: Set<DiMLSOperations<C>>,
            pendingFollowOps: [DiMLS.ReferenceID: DiMLSOperations<C>]
        ) {
            self.applicationRequestsNewKeyDistribution = applicationRequestsNewKeyDistribution
            self.pendingLocalOps = pendingLocalOps
            self.pendingFollowOps = pendingFollowOps
        }

        //MARK: Archive
        public struct Archive: Sendable, Codable {
            let applicationRequestsNewKeyDistribution: Bool
            let pendingLocalOps: [DiMLSOperations<C>.Archive]
            //this includes incorporating PCS updates
            let pendingFollowOps: [DiMLS.ReferenceID: DiMLSOperations<C>.Archive]
        }

        public init(archive: Archive) throws {
            self.applicationRequestsNewKeyDistribution =
                archive.applicationRequestsNewKeyDistribution
            self.pendingLocalOps = try .init(
                archive.pendingLocalOps.map {
                    try .init(archive: $0)
                })
            self.pendingFollowOps = try archive.pendingFollowOps
                .mapValues { try .init(archive: $0) }
        }

        public var archive: Archive {
            get throws {
                .init(
                    applicationRequestsNewKeyDistribution: applicationRequestsNewKeyDistribution,
                    pendingLocalOps: try pendingLocalOps.map { try $0.archive },
                    pendingFollowOps: try pendingFollowOps.mapValues { try $0.archive },
                )
            }
        }

        public var commitNeeded: Bool {
            applicationRequestsNewKeyDistribution || !pendingLocalOps.isEmpty
                || !pendingFollowOps.isEmpty
        }

        public func stageAdd(member: DiMLS.CredentialedKeyPackage<C>) throws {
            pendingLocalOps.insert(.add(member))
        }

        func committed(input: CommitInput<C>) {
            for localOp in input.localOps {
                pendingLocalOps.remove(localOp)
            }
        }
    }
}

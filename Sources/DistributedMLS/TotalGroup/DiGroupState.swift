//
//  TotalGroup.swift
//  DiMLS
//
//  Created by Mark @ Germ on 12/29/25.
//

import Foundation

//state of the observed group, including (permanently) removed members
public final class DiGroupState<Credential: DiMLSCredential> {
    ///we can join at any time, and don't need to reconstruct adds from the group membership
    public private(set) var members: [DiMLS.ReferenceID: Membership]

    public var count: Int { members.count }

    private init(members: [DiMLS.ReferenceID: Membership]) {
        self.members = members
    }

    public convenience init(archive: Archive) throws {
        self.init(
            members: try archive.members.mapValues { try .init(archive: $0) },
        )
    }

    public func canAdd(_ member: DiMLS.ReferenceID) -> Bool {
        !members.keys.contains(member)
    }

    public func add(member: Credential) throws {
        guard canAdd(member.referenceId) else {
            throw DiMLSError.duplicateMember
        }
        assert(members[member.referenceId] == nil)
        members[member.referenceId] = .new(credential: member)
    }

    //    public func added(member: DiMLS.ReferenceID) throws {
    //        guard canAdd(member) else {
    //            throw DiMLSError.disallowed
    //        }
    //        members.insert(member)
    //    }

    func membershipForCreating(
        sender: DiMLS.ReferenceID
    ) -> [DiMLS.ReferenceID: DiMLS.Participant<Credential>] {
        members.compactMapValues { membership in
            guard membership.referenceId != sender else {
                return nil
            }
            let epoch = membership.epochs.last
            if let epoch {
                return .credential(epoch.credential, epoch.epoch)
            } else {
                return .referenceId(membership.referenceId)
            }
        }
    }
}

extension DiGroupState: Archivable {
    public struct Archive: Codable, Sendable {
        public let members: [DiMLS.ReferenceID: Membership.Archive]
        //array makes it easier to encode stably over the wire

        public init(members: [DiMLS.ReferenceID: Membership.Archive]) {
            self.members = members
        }
    }

    public var archive: Archive {
        .init(
            members: members.mapValues(\.archive),
        )
    }
}

extension DiGroupState {
    public struct Membership {
        let referenceId: DiMLS.ReferenceID
        //can prune, but should never prune to empty as
        //empty indicates invited
        public private(set) var epochs: [Epoch]  //should be in increasing epoch order

        static func new(credential: Credential) -> Self {
            .init(
                referenceId: credential.referenceId,
                epochs: []
            )
        }

        init(referenceId: DiMLS.ReferenceID, epochs: [Epoch]) {
            self.referenceId = referenceId
            self.epochs = epochs
        }

        public struct Epoch: Archivable {
            let epoch: UInt64
            public let credential: Credential

            init(epoch: UInt64, credential: Credential) {
                self.epoch = epoch
                self.credential = credential
            }

            public init(archive: Archive) throws {
                self.init(
                    epoch: archive.epoch,
                    credential: try .init(encoded: archive.credential)
                )
            }

            public struct Archive: Codable, Sendable {
                let epoch: UInt64
                let credential: Data

                public init(epoch: UInt64, credential: Data) {
                    self.epoch = epoch
                    self.credential = credential
                }
            }

            var archive: Archive {
                .init(epoch: epoch, credential: credential.encoded)
            }
        }
    }
}

extension DiGroupState.Membership: Archivable {
    public struct Archive: Codable, Sendable {
        let referenceId: DiMLS.ReferenceID
        let epochs: [Epoch.Archive]

        public init(referenceId: DiMLS.ReferenceID, epochs: [Epoch.Archive]) {
            self.referenceId = referenceId
            self.epochs = epochs
        }

        public static func create(referenceId: DiMLS.ReferenceID) -> Self {
            .init(referenceId: referenceId, epochs: [])
        }

        public static func create(
            referenceId: DiMLS.ReferenceID,
            credential: Data,
            epoch: UInt64
        ) -> Self {
            .init(
                referenceId: referenceId,
                epochs: [
                    .init(
                        epoch: epoch,
                        credential: credential
                    )
                ]
            )
        }
    }

    public init(archive: Archive) throws {
        referenceId = archive.referenceId
        epochs = try archive.epochs.map { try .init(archive: $0) }
    }

    var archive: Archive {
        .init(
            referenceId: referenceId,
            epochs: epochs.map(\.archive)
        )
    }
}

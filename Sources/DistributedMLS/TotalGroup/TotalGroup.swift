//
//  TotalGroup.swift
//  DiMLS
//
//  Created by Mark @ Germ on 12/29/25.
//

import Foundation

//state of the observed group, including (permanently) removed members
extension DiMLS {
    public final class TotalGroup<Credential: DiMLSCredential> {
        ///we can join at any time, and don't need to reconstruct adds from the group membership
        public private(set) var members: [ReferenceID: Membership]

        public var count: Int { members.count }

        private init(members: [ReferenceID: Membership]) {
            self.members = members
        }

        public convenience init(archive: Archive) throws {
            self.init(
                members: try archive.members.mapValues { try .init(archive: $0) },
            )
        }

        public func canAdd(_ member: ReferenceID) -> Bool {
            !members.keys.contains(member)
        }

        public func add(member: Credential) throws {
            guard canAdd(member.referenceId) else {
                throw DiMLSError.duplicateMember
            }
            assert(members[member.referenceId] == nil)
            members[member.referenceId] = .new(dependency: nil)
        }

        public func readyToWelcome(member: ReferenceID) throws {
            try members[member].tryUnwrap
                .readyToWelcome(member: member)
        }

        func welcomed(member: Membership.Epoch) throws {
            let referenceId = member.senderCredential.referenceId
            guard case .invited = members[referenceId] else {
                throw DiMLSError.disallowed
            }

            let existing = try members[referenceId].tryUnwrap
            members[referenceId] = try existing.welcomed(epoch: member)
        }

        func invited(
            member: ReferenceID,
            keyedDependency: DiMLS.KeyedDependency
        ) throws {
            if let existing = members[member] {
                guard case .invited(let array) = existing else {
                    return
                }
                members[member] = .invited(array + [keyedDependency])
            } else {
                members[member] = .invited([keyedDependency])
            }
        }

        func committed(
            referenceId: DiMLS.ReferenceID,
            epoch: Membership.Epoch
        ) throws {
            let existing = try members[referenceId].tryUnwrap
            members[referenceId] = try existing.committed(epoch: epoch)
        }
    }
}

extension DiMLS.TotalGroup: Archivable {
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

extension DiMLS.TotalGroup {
    public enum Membership {
        //can be empty so that as an identity provider it allows me to add them,
        //then lets me fill in the dependency
        case invited([DiMLS.KeyedDependency])
        case known  //I did not see the initial invite
        case claimed([Epoch])

        static func new(
            dependency: DiMLS.KeyedDependency?
        ) -> Self {
            .invited([dependency].compactMap(\.self))
        }

        public struct Epoch: Archivable {
            let epoch: DiMLS.EpochID
            public let senderCredential: Credential
            public var recipients: [Recipient]
            //can efface this when fully ack'd
            var keyedDependency: DiMLS.KeyedDependency?

            //acknowledge other groups
            let newDependencies: [DiMLS.ReferenceID: DiMLS.EpochID]

            //accumulate these and don't accept rollbacks
            let baseDependencies: [DiMLS.ReferenceID: DiMLS.EpochID]

            public init(
                epoch: DiMLS.EpochID,
                senderCredential: Credential,
                recipients: [Recipient],
                keyedDependency: DiMLS.KeyedDependency?,
                newDependencies: [DiMLS.ReferenceID: DiMLS.EpochID],
                baseDependencies: [DiMLS.ReferenceID: DiMLS.EpochID]
            ) {
                self.epoch = epoch
                self.senderCredential = senderCredential
                self.recipients = recipients
                self.keyedDependency = keyedDependency
                self.newDependencies = newDependencies
                self.baseDependencies = baseDependencies
            }

            public init(archive: Archive) throws {
                self.init(
                    epoch: archive.epoch,
                    senderCredential: try .init(encoded: archive.credential),
                    recipients: try archive.recipients
                        .map { try .init(archive: $0) },
                    keyedDependency: archive.keyedDependency,
                    newDependencies: archive.newDependencies,
                    baseDependencies: archive.baseDependencies
                )
            }

            public struct Archive: Codable, Sendable {
                let epoch: DiMLS.EpochID
                let credential: Data
                let recipients: [Recipient.Archive]
                let keyedDependency: DiMLS.KeyedDependency?
                let newDependencies: [DiMLS.ReferenceID: DiMLS.EpochID]
                let baseDependencies: [DiMLS.ReferenceID: DiMLS.EpochID]

                public init(
                    epoch: DiMLS.EpochID,
                    credential: Data,
                    recipients: [Recipient.Archive],
                    keyedDependency: DiMLS.KeyedDependency?,
                    newDependencies: [DiMLS.ReferenceID: DiMLS.EpochID],
                    baseDependencies: [DiMLS.ReferenceID: DiMLS.EpochID]
                ) {
                    self.epoch = epoch
                    self.credential = credential
                    self.recipients = recipients
                    self.keyedDependency = keyedDependency
                    self.newDependencies = newDependencies
                    self.baseDependencies = baseDependencies
                }
            }

            var archive: Archive {
                .init(
                    epoch: epoch,
                    credential: senderCredential.encoded,
                    recipients: recipients.map(\.archive),
                    keyedDependency: keyedDependency,
                    newDependencies: newDependencies,
                    baseDependencies: baseDependencies
                )
            }
        }

        func readyToWelcome(member: DiMLS.ReferenceID) throws {
            guard case .invited = self else {
                throw DiMLSError.duplicateMember
            }
        }

        func welcomed(epoch: Epoch) throws -> Membership {
            switch self {
            case .known, .invited:
                break
            case .claimed(let array):
                throw DiMLSError.disallowed
            }

            return .claimed([epoch])

        }

        func committed(epoch: Epoch) throws -> Membership {
            guard case .claimed(let epochs) = self else {
                throw DiMLSError.disallowed
            }
            let newest = try epochs.last.tryUnwrap
            assert(newest.epoch + 1 == epoch.epoch)

            var newBase = newest.baseDependencies
            for (key, value) in epoch.newDependencies {
                if let existing = newBase[key] {
                    assert(value > existing)
                    newBase[key] = value
                }
            }

            let newEpoch = Epoch(
                epoch: epoch.epoch,
                senderCredential: epoch.senderCredential,
                recipients: epoch.recipients,
                keyedDependency: epoch.keyedDependency,
                newDependencies: epoch.newDependencies,
                baseDependencies: epoch.baseDependencies
            )

            return .claimed(epochs + [epoch])

        }
    }
}

extension DiMLS.TotalGroup.Membership: Archivable {
    public enum Archive: Codable, Sendable {
        case invited([DiMLS.KeyedDependency])
        case known
        case claimed([Epoch.Archive])
    }

    public init(archive: Archive) throws {
        switch archive {
        case .claimed(let epochs):
            self = .claimed(try epochs.map { try .init(archive: $0) })
        case .invited(let dependencies):
            self = .invited(dependencies)
        case .known:
            self = .known
        }
    }

    var archive: Archive {
        switch self {
        case .claimed(let epochs):
            .claimed(epochs.map(\.archive))
        case .invited(let dependencies):
            .invited(dependencies)
        case .known:
            .known
        }
    }
}

extension DiMLS.TotalGroup.Membership.Epoch {
    public struct Recipient: Archivable {
        let credential: Credential
        var acknowledged: Bool

        public init(credential: Credential, acknowledged: Bool) {
            self.credential = credential
            self.acknowledged = acknowledged
        }

        public init(archive: Archive) throws {
            self.init(
                credential: try .init(encoded: archive.credential),
                acknowledged: archive.acknowledged
            )
        }

        public struct Archive: Codable, Sendable {
            let credential: Data
            let acknowledged: Bool

            public init(credential: Data, acknowledged: Bool) {
                self.credential = credential
                self.acknowledged = acknowledged
            }
        }

        var archive: Archive {
            .init(credential: credential.encoded, acknowledged: acknowledged)
        }
    }
}

extension DiMLS.TotalGroup {
    public var knownDependencies: [DiMLS.KeyedDependency] {
        members.values.reduce(into: []) { result, member in
            switch member {
            case .invited(let dependencies):
                result += dependencies
            case .known: break
            case .claimed(let epochs):
                result += epochs.compactMap(\.keyedDependency)
            }
        }
    }
}

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

        //    public func added(member: DiMLS.ReferenceID) throws {
        //        guard canAdd(member) else {
        //            throw DiMLSError.disallowed
        //        }
        //        members.insert(member)
        //    }

        func membershipForCreating(
            sender: ReferenceID
        ) throws -> [ReferenceID: Participant<Credential>] {
            try members.reduce(into: [:]) {
                result,
                pair in
                guard pair.key != sender else {
                    return
                }
                assert(result[pair.key] == nil)
                switch pair.value {
                case .invited(let dependencies):
                    result[pair.key] = .referenceId(pair.key)
                case .claimed(let epochs):
                    let epoch = try epochs.last.tryUnwrap
                    result[pair.key] = .credential(
                        epoch.credential,
                        epoch.epoch
                    )
                }
            }
        }

        public func readyToWelcome(member: ReferenceID) throws {
            try members[member].tryUnwrap
                .readyToWelcome(member: member)
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
        case claimed([Epoch])

        static func new(
            dependency: DiMLS.KeyedDependency?
        ) -> Self {
            .invited([dependency].compactMap(\.self))
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

        func readyToWelcome(member: DiMLS.ReferenceID) throws {
            guard case .invited = self else {
                throw DiMLSError.duplicateMember
            }
        }
    }
}

extension DiMLS.TotalGroup.Membership: Archivable {
    public enum Archive: Codable, Sendable {
        case invited([DiMLS.KeyedDependency])
        case claimed([Epoch.Archive])

        public static func create(
            credential: Data,
            epoch: UInt64
        ) -> Self {
            .claimed([.init(epoch: epoch, credential: credential)])
        }
    }

    public init(archive: Archive) throws {
        switch archive {
        case .claimed(let epochs):
            self = .claimed(try epochs.map { try .init(archive: $0) })
        case .invited(let dependencies):
            self = .invited(dependencies)
        }
    }

    var archive: Archive {
        switch self {
        case .claimed(let epochs):
            .claimed(epochs.map(\.archive))
        case .invited(let dependencies):
            .invited(dependencies)
        }
    }
}

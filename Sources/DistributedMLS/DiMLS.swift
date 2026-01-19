//
//  DiMLS.swift
//  DiMLS
//
//  Created by Mark @ Germ on 12/8/25.
//

import Foundation

public enum DiMLS {
    public typealias ReferenceID = Data
    public typealias EpochID = UInt64
    public typealias KeyPackageId = Data

    ///mirrors (is a) MLS private message in that it has an encrypted
    ///application message and plaintext metadata and auth data
    ///This is an output of the ratchet tree for a given context, which is addressed to a specific snapshot
    ///of the collective group.
    public struct PrivateMessage<C: DiMLSCredential>: Sendable {
        public let body: Data  //encoded MLS Private message
        public let epoch: EpochID  //we may retry transmit after a later commit
        public let sender: C
        public let addressees: [C]

        public init(
            body: Data,
            epoch: EpochID,
            sender: C,
            addressees: [C]
        ) {
            self.body = body
            self.epoch = epoch
            self.sender = sender
            self.addressees = addressees
        }
    }

    public enum DecryptOutput {
        case control  //todo: type out the control plane message
        case application(plaintext: Data)
    }

    public struct EncryptOutput: Sendable {
        //Implementation may choose to staple the commit and/or
        //encrypt headers
        public let privateMessage: Data
        //if not stapled let the caller judge if it wants resend the commit
        public let epoch: EpochID
        public let additionalCommits: [EpochCommit]

        public init(
            privateMessage: Data,
            epoch: EpochID,
            additionalCommits: [EpochCommit]
        ) {
            self.privateMessage = privateMessage
            self.epoch = epoch
            self.additionalCommits = additionalCommits
        }
    }

    public struct EpochCommit: Sendable, Codable {
        public let epoch: EpochID
        public let commit: Data

        public init(epoch: EpochID, commit: Data) {
            self.epoch = epoch
            self.commit = commit
        }
    }

    //in theory, C should be contained in and extractable from the keyPackage,
    //but that requires knowledge of the implementation. For modularity we
    //save it in the bare so we can reason about it before reaching into
    //the MLS implementation
    public struct CredentialedKeyPackage<C: DiMLSCredential>: Hashable, Sendable {
        public let credential: C
        public let keyPackage: Data  // MLS Keypackage message

        public init(
            credential: C,
            keyPackage: Data
        ) {
            self.credential = credential
            self.keyPackage = keyPackage
        }

        public init(archive: Archive) throws {
            self.credential = try .init(encoded: archive.credential)
            self.keyPackage = archive.keyPackage
        }
    }
}

extension DiMLS.CredentialedKeyPackage: Archivable {
    public struct Archive: Sendable, Codable {
        let credential: Data
        let keyPackage: Data
    }

    var archive: Archive {
        .init(credential: credential.encoded, keyPackage: keyPackage)
    }
}

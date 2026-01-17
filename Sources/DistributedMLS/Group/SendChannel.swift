//
//  SendChannel.swift
//  DiMLS
//
//  Created by Mark @ Germ on 1/6/26.
//

import Foundation

//not Archivable as it can't be initialized from a bare archive object
public protocol SendChannel {
    associatedtype Credential: DiMLSCredential
    associatedtype Archive: Sendable, Codable
    associatedtype IdentityProvider

    associatedtype Commit
    associatedtype Welcome

    static func identityProvider(
        totalGroup: DiGroupState<Credential>,
        sender: Credential
    ) -> IdentityProvider

    static func create(
        input: SendChannelInputs<Credential>,
        identityProvider: IdentityProvider
    ) throws -> Archive

    init(archive: Archive, identityProvider: IdentityProvider) throws

    var archive: Archive { get throws }

    func currentEpoch() -> UInt64

    func commit(input: DiMLS.CommitInput<Credential>) throws -> (
        commitMessage: Commit,
        welcomes: [Welcome]
    )
    //packaging the encrypted app message with metadata can all be done
    //in the send channel
    func encrypt(plaintext: Data, authenticating: Data) throws -> [(
        Credential, DiMLS.EncryptOutput
    )]

}

public struct SendChannelInputs<Credential: DiMLSCredential> {
    public let diGroupID: Data
    public let myCredential: Credential
    public let remotes: [DiMLS.ReferenceID: Remote]

    public struct Remote {
        public let keyPackage: DiMLS.CredentialedKeyPackage<Credential>
        //which epoch this credential corresponds to
        public let theirEpoch: UInt64?

        public init(
            keyPackage: DiMLS.CredentialedKeyPackage<Credential>,
            theirEpoch: UInt64?
        ) {
            self.keyPackage = keyPackage
            self.theirEpoch = theirEpoch
        }
    }

    public var correspondingRecipientEpoch: [DiMLS.ReferenceID: UInt64] {
        remotes.reduce(into: [:]) { result, remote in
            if let epoch = remote.value.theirEpoch {
                assert(result[remote.key] == nil)
                result[remote.key] = epoch
            }
        }
    }
}

public enum LazySendChannel<R: SendChannel> {
    case ready(R)
    case queued
    //serves as a mutex on snapshot of Q state
    case creating(Task<Void, Error>)

    public init(
        archive: Archive,
        identityProvider: R.IdentityProvider
    ) throws {
        switch archive {
        case .ready(let archive):
            self = .ready(
                try .init(archive: archive, identityProvider: identityProvider)
            )
        case .queued:
            self = .queued
        }
    }

    var readyChannel: R {
        get throws {
            guard case .ready(let r) = self else {
                throw DiMLSError.sendGroupNotReady
            }
            return r
        }
    }
}

extension LazySendChannel {
    public enum Archive: Sendable, Codable {
        case ready(R.Archive)
        case queued
    }

    public var archive: Archive {
        get throws {
            switch self {
            case .ready(let r):
                try .ready(r.archive)
            case .queued:
                try .queued
            case .creating:
                try .queued
            }
        }
    }
}

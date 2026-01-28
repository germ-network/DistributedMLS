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
        totalGroup: DiMLS.TotalGroup<Credential>,
        sender: Credential
    ) -> IdentityProvider

    static func create(
        input: SendChannelInputs<Credential>,
        identityProvider: IdentityProvider,
        dependency: DiMLS.KeyedDependency?
    ) throws -> (Archive, DiMLS.TotalGroup<Credential>.Membership.Epoch)

    init(
        archive: Archive,
        diGroupId: Data,
        identityProvider: IdentityProvider
    ) throws

    var archive: Archive { get throws }

    func currentEpoch() -> UInt64

    func commit(input: DiMLS.CommitInput<Credential>) throws -> (
        commitMessage: Commit,
        welcomes: [Welcome],
        historyEpoch: DiMLS.TotalGroup<Credential>.Membership.Epoch
    )
    //packaging the encrypted app message with metadata can all be done
    //in the send channel
    func encrypt(plaintext: Data, authenticating: Data) throws -> [Credential: DiMLS.EncryptOutput]

    var recipients: [Credential] { get throws }

    func exportDependencyKey(diGroupContext: Data) throws -> Data
}

public struct SendChannelInputs<Credential: DiMLSCredential> {
    public let snapshotId: UUID
    public let diGroupID: Data
    public let myCredential: Credential
    public let remotes: [DiMLS.ReferenceID: Remote]
    //for now, can only refer to a single group when distributing welcomes
    public let dependency: DiMLS.KeyedDependency?

    public init(
        snapshotId: UUID,
        diGroupID: Data,
        myCredential: Credential,
        remotes: [DiMLS.ReferenceID: Remote],
        dependency: DiMLS.KeyedDependency?
    ) {
        self.snapshotId = snapshotId
        self.diGroupID = diGroupID
        self.myCredential = myCredential
        self.remotes = remotes
        self.dependency = dependency
    }

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

        public enum Snapshot {
            case invited
            case known(Credential)
            case joined(epoch: UInt64, credential: Credential)

            public var epoch: UInt64? {
                switch self {
                case .invited, .known:
                    nil
                case .joined(let epoch):
                    epoch.epoch
                }
            }
        }
    }

    //get keypackages for these remotes and give me back a SendChannelInputs when done
    public struct Snapshot {
        public let id = UUID()
        public let diGroupID: Data
        public let remotes: [DiMLS.ReferenceID: Remote.Snapshot]
        //for now, can only refer to a single group when distributing welcomes
        public let dependency: DiMLS.KeyedDependency?
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

    //we want to externalize the async fetching of keyPackages
    //so we allow for the app to ask for a membership set, freezing it
    //then come back async to init that version
    //it is ok for us to miss some updates in the interim
    case preparing(SendChannelInputs<R.Credential>.Snapshot)

    public init(
        archive: Archive,
        diGroupId: Data,
        identityProvider: R.IdentityProvider
    ) throws {
        switch archive {
        case .ready(let archive):
            self = .ready(
                try .init(
                    archive: archive,
                    diGroupId: diGroupId,
                    identityProvider: identityProvider
                )
            )
        case .queued:
            self = .queued
        }
    }

    public var readyChannel: R {
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
            case .queued, .preparing:
                .queued
            }
        }
    }
}

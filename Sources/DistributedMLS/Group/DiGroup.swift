//
//  Group.swift
//  DiMLS
//
//  Created by Mark @ Germ on 11/24/25.
//

import Foundation

//higher level abstraction for the Local /
extension DiMLS {
    public protocol DiGroup: AnyObject, Archivable {
        associatedtype Credential: DiMLSCredential

        //State Types
        associatedtype Receiver: ReceiveChannel
        where Receiver.WelcomeOutput.Credential == Credential
        associatedtype Sender: SendChannel where Sender.Credential == Credential

        //Archivable
        var archive: Archive { get throws }

        //associated State
        //mutable object

        nonisolated var diGroupId: Data { get }
        nonisolated var myReferenceId: Data { get }
        var totalGroup: DiMLS.TotalGroup<Credential> { get }
        var receivers: [ReferenceID: Receiver] { get set }
        var pendingState: PendingState<Credential> { get }
        var lazySender: LazySendChannel<Sender> { get set }

        func stageAdd(member: DiMLS.CredentialedKeyPackage<Credential>) throws

        //the prototype can't do all operations in a single commit
        //(add + dependency), so we let the implementation modify the pending
        //state to pop off the actions it can make progress on
        func prepareCommit() throws -> DiMLS.CommitInput<Credential>
        //different interface as it is initially handled by the init key
        //corresponding to a keyPackage
        //if we know we can process directly with the symmetric ratchet
        func received(privateMessage: Data) throws -> AppPlaintext

        //        func stageNewLocalKeyMaterial() throws
    }
}

extension DiMLS.DiGroup {
    public typealias CredentialKeyPackageFetcher = (Credential) async throws -> Data
    public typealias ReferenceIdKeyPackageFetcher = (
        DiMLS.ReferenceID
    ) async throws -> DiMLS.CredentialedKeyPackage<Credential>

    public var needsSendChannelSetup: Bool {
        guard case .queued = lazySender else {
            return false
        }
        return true
    }

    public func prepareSendChannelSetup()
        throws -> SendChannelInputs<Credential>.Snapshot
    {
        switch lazySender {
        //can call this repeatedly to get a newer membership list
        case .ready:
            throw DiMLSError.sendGroupCreated
        default:
            break
        }

        //can't construct group de novo by unioning when joining,
        //need to consult the existing groups
        //to find the widest one to references
        let referenceEpoch = try chooseReceiver()
        let referenceSender = referenceEpoch.senderCredential

        var remotes = [DiMLS.ReferenceID: SendChannelInputs<Credential>.Remote.Snapshot]()
        remotes[referenceSender.referenceId] =
            .joined(
                epoch: referenceEpoch.epoch,
                credential: referenceSender
            )
        for recipient in referenceEpoch.recipients {
            guard recipient.credential.referenceId != myReferenceId else {
                continue
            }

            switch totalGroup.members[recipient.credential.referenceId] {
            case .claimed(let epochs):
                let epoch = try epochs.last.tryUnwrap
                remotes[recipient.credential.referenceId] =
                    .joined(
                        epoch: epoch.epoch,
                        credential: epoch.senderCredential
                    )
            case .invited:
                remotes[recipient.credential.referenceId] =
                    .invited
            case .known:
                remotes[recipient.credential.referenceId] =
                    .known(recipient.credential)
            case .none:
                throw DiMLSError.disallowed
            }
        }

        let snapshot = SendChannelInputs<Credential>.Snapshot(
            diGroupID: diGroupId,
            remotes: remotes,
            dependency: try referenceEpoch.keyedDependency.tryUnwrap
        )
        lazySender = .preparing(snapshot)
        return snapshot
    }

    private func chooseReceiver() throws -> DiMLS.TotalGroup<Self.Credential>.Membership.Epoch {
        var choice: DiMLS.TotalGroup<Self.Credential>.Membership.Epoch? = nil
        for (id, receiver) in totalGroup.members {
            guard id != myReferenceId else {
                continue
            }
            guard case .claimed(let epochs) = receiver else {
                continue
            }
            let epoch = try epochs.last.tryUnwrap
            if let _choice = choice {
                if _choice.recipients.count < epoch.recipients.count {
                    choice = epoch
                    //TODO, if set equality, compare individual epochs
                }
            } else {
                choice = epoch
            }
        }
        return try choice.tryUnwrap
    }

    public func setupChannel(input: SendChannelInputs<Credential>) throws {
        guard case .preparing(let stagedInput) = lazySender else {
            throw DiMLSError.sendGroupNotReady
        }
        guard input.snapshotId == stagedInput.id else {
            throw DiMLSError.reentrantCreateCall
        }

        do {
            let archive = try createSendGroup(input: input)

            let identityProvider = Sender.identityProvider(
                totalGroup: totalGroup,
                sender: input.myCredential
            )

            lazySender = .ready(
                try .init(
                    archive: archive,
                    diGroupId: diGroupId,
                    identityProvider: identityProvider
                )
            )
        } catch {
            print("error creating: \(error)")
            lazySender = .queued
            throw error
        }
    }

    private func createSendGroup(input: SendChannelInputs<Credential>) throws -> Sender.Archive {
        return try Sender.create(
            input: input,
            identityProvider: Sender.identityProvider(
                totalGroup: totalGroup,
                sender: input.myCredential
            ),
            dependency: input.dependency
        )

    }

    public func encryptWithCommits(
        plaintext: Data,
        authenticating: Data,
        staplingCommit: Bool
    ) throws -> [Credential: DiMLS.EncryptOutput] {
        let sender = try lazySender.readyChannel

        //commit if necessary
        let commitEffect = try commitIfNecessary(sender: sender)

        return try sender.encrypt(
            plaintext: plaintext,
            authenticating: authenticating
        )
    }

    private func commitIfNecessary(
        sender: Sender
    ) throws -> DiMLS.LocalCommitEffect<Credential>? {
        guard pendingState.commitNeeded else {
            return nil
        }

        let input = try prepareCommit()

        return try commit(input: input, sender: sender)
    }

    private func commit(
        input: DiMLS.CommitInput<Credential>,
        sender: Sender,
    ) throws -> DiMLS.LocalCommitEffect<Credential> {
        var newRemotes: [DiMLS.CredentialedKeyPackage<Credential>] = []

        //modify remotes and group
        for action in input.localOps {
            switch action {
            case .add(let credentialKeyPackage):
                newRemotes.append(credentialKeyPackage)
                //have to add to the total group that serves as a identity provider
                try totalGroup.add(member: credentialKeyPackage.credential)
            }
        }

        let sendChannel = try lazySender.readyChannel

        //TODO: these are unused
        let (commitMessage, welcome) = try sendChannel.commit(input: input)
        pendingState.committed(input: input)

        if !newRemotes.isEmpty {

            for newRemote in newRemotes {
                let referenceId = newRemote.credential.referenceId

                guard receivers[referenceId] == nil else {
                    throw DiMLSError.duplicateMember
                }
            }
        }

        return .init(
            didIntroduceNewPubKey: input.newSenderLeafNode,
            localOps: [],
            followOps: [],
            dependencies: [:]
        )
    }

    public func received(
        welcome: Receiver.WelcomeOutput,
        myCredential: Credential,
    ) throws -> DiMLS.AppPlaintext? {
        guard welcome.diGroupId == diGroupId else {
            throw DiMLSError.mismatchedGroupId
        }

        let senderReferenceId = try welcome.senderReferenceId

        //is this a member of the group?
        try totalGroup
            .readyToWelcome(member: welcome.senderReferenceId)

        guard receivers[senderReferenceId] == nil else {
            throw DiMLSError.duplicateMember
        }
        receivers[senderReferenceId] = try .create(welcome: welcome)
        try totalGroup.welcomed(
            member: try welcome.membershipEpoch(myCredential: myCredential)
        )

        guard let appMessage = welcome.appPrivateMessage else {
            return nil
        }
        return try receivers[senderReferenceId].tryUnwrap
            .decrypt(messageData: appMessage)

    }

    public func received(
        ciphertext: Data,
        //helpful to have a hint here or you have to cycle through each send group
        //as we use 1:1 channels this can be imferred from the channel
        senderHint: DiMLS.ReferenceID?
    ) throws -> DiMLS.DecryptOutput<Credential> {
        let matching: [Receiver] = try {
            return if let senderHint {
                [try receivers[senderHint].tryUnwrap]
            } else {
                .init(receivers.values)
            }
        }()

        for receiver in matching {
            if let result = try receiver.received(
                ciphertext: ciphertext,
                diGroupId: diGroupId
            ) {
                if let commitResult = result.commitResult {
                    for added in commitResult.added {
                        try totalGroup.invited(
                            member: added.referenceId,
                            keyedDependency: commitResult.keyedDependency
                        )
                    }
                }

                return result
            }
        }

        throw DiMLSError.decryptFallthrough
    }
}

//we have a generic (Credential) and a non-generic and could simplify them
public enum DiMLSOperations<C: DiMLSCredential>: Sendable {
    case add(DiMLS.CredentialedKeyPackage<C>)

    public init(archive: Archive) throws {
        switch archive {
        case .add(let archive):
            self = .add(try .init(archive: archive))
        }
    }

    public var description: String {
        switch self {
        case .add(let c):
            "add \(c)"
        }
    }

    public var adding: DiMLS.CredentialedKeyPackage<C>? {
        guard case .add(let credential) = self else {
            return nil
        }
        return credential
    }
}

extension DiMLSOperations: Hashable {}

extension DiMLSOperations: Archivable {
    public enum Archive: Codable, Sendable {
        case add(DiMLS.CredentialedKeyPackage<C>.Archive)
    }

    public var archive: Archive {
        get throws {
            switch self {
            case .add(let credentialedKeyPackage):
                .add(credentialedKeyPackage.archive)
            }
        }
    }
}

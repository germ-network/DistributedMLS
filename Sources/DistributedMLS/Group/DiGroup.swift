//
//  Group.swift
//  DiMLS
//
//  Created by Mark @ Germ on 11/24/25.
//

import Foundation

//higher level abstraction for the Local /
extension DiMLS {
    public protocol DiGroup: Actor, Archivable {
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
        func received(
            ciphertext: Data,
            senderHint: DiMLS.ReferenceID?
        ) throws -> DecryptOutput
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

    public func setupChannel(
        myCredential: Credential,
        credentialFetcher: @escaping CredentialKeyPackageFetcher,
        referenceIdFetcher: @escaping ReferenceIdKeyPackageFetcher
    ) throws -> Task<Void, Error> {
        guard case .queued(let dependency) = lazySender else {
            if case .creating(let task, _) = lazySender {
                return task
            }
            throw DiMLSError.sendGroupNotReady
        }
        let task = Task {
            do {
                let archive = try await createSendGroup(
                    myCredential: myCredential,
                    members:
                        totalGroup
                        .membershipForCreating(sender: myCredential.referenceId),
                    dependency: dependency,
                    credentialFetcher: credentialFetcher,
                    referenceIdFetcher: referenceIdFetcher
                )

                let identityProvider = Sender.identityProvider(
                    totalGroup: totalGroup,
                    sender: myCredential
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
                lazySender = .queued(dependency)
                throw error
            }
        }
        lazySender = .creating(task, dependency)
        return task
    }

    private func createSendGroup(
        myCredential: Credential,
        members: [DiMLS.ReferenceID: DiMLS.Participant<Self.Credential>],
        dependency: DiMLS.KeyedDependency?,
        credentialFetcher: CredentialKeyPackageFetcher,
        referenceIdFetcher: ReferenceIdKeyPackageFetcher
    ) async throws -> Sender.Archive {

        //capture a snapshot of what the group needs
        var remotes = [DiMLS.ReferenceID: SendChannelInputs<Credential>.Remote]()

        let members =
            try totalGroup
            .membershipForCreating(sender: myCredential.referenceId)
        for member in members {
            switch member.value {
            case .credential(let credential, let epoch):
                let keyPackage = try await credentialFetcher(credential)

                remotes[member.key] = .init(
                    keyPackage: .init(
                        credential: credential,
                        keyPackage: keyPackage
                    ),
                    theirEpoch: epoch
                )
            case .referenceId(let referenceId):
                remotes[member.key] = .init(
                    keyPackage: try await referenceIdFetcher(referenceId),
                    theirEpoch: nil
                )
            }
        }

        return try Sender.create(
            input: .init(
                diGroupID: diGroupId,
                myCredential: myCredential,
                remotes: remotes
            ),
            identityProvider: Sender.identityProvider(
                totalGroup: totalGroup,
                sender: myCredential
            ),
            dependency: dependency
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

    public func received(welcome: Receiver.WelcomeOutput) throws -> DiMLS.AppPlaintext? {
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
        try totalGroup.welcomed(member: try welcome.membershipEpoch)

        guard let appMessage = welcome.appPrivateMessage else {
            return nil
        }
        return try receivers[senderReferenceId].tryUnwrap
            .decrypt(messageData: appMessage)

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

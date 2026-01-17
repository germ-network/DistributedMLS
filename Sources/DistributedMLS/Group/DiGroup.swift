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
        associatedtype Sender: SendChannel where Sender.Credential == Credential

        associatedtype WelcomeOutput: WelcomeOutputInterface

        //Archivable
        var archive: Archive { get throws }

        //associated State
        //mutable object

        var totalGroup: DiGroupState<Credential> { get }
        var receivers: [ReferenceID: Receiver] { get set }
        var pendingState: PendingState<Credential> { get }
        var lazySender: LazySendChannel<Sender> { get set }

        func stageAdd(member: DiMLS.CredentialedKeyPackage<Credential>) throws

        //the prototype can't do all operations in a single commit
        //(add + dependency), so we let the implementation modify the pending
        //state to pop off the actions it can make progress on
        func prepareCommit() throws -> DiMLS.CommitInput<Credential>
        func received(welcome: WelcomeOutput) throws

        //Deprecate:
        ///DiGgroup Operations
        //        associatedtype RemoteState: RemoteStateInterface
        //        var remoteStates: [ReferenceID: RemoteState] { get }

        //Local mutations only have meaning when I broadcast them into the world
        //        func stageAdd(member: DiMLS.CredentialedKeyPackage<Credential>) throws
        //        func stageDelete(member: Credential) throws
        //        //application should drive if new key material is needed
        //        func stageNewLocalKeyMaterial() throws

        ///DiGroup 1:1 Control Plane
        ///expect sender crendential implicit in assigned transport path
        //        func receive(ciphertext: Data, from: Credential) throws -> DiMLS.DecryptOutput

        //let the application get and resend unack'd commits
        //TODO: attach metadata to the result like an epoch no
        //        func inFlightFor(remote: Credential) throws -> [Data]

        //Application messages
        //this will commit any pending changes
        //TODO: also report state changes
        //for now, authenticated data is included in the output
        //(because MLS does in the PrivateMessage format)
        //returns private message and recipients
        //        func encrypt(plaintext: Data, authenticating: Data) throws
        //            -> DiMLS.PrivateMessage<Credential>
        //        func stapledEncrypt(plaintext: Data) throws
        //            -> DiMLS.PrivateMessage<Credential>

        //process incoming, which may be an application message, commit
        //or a welcome to another user's send group

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
        guard case .queued = lazySender else {
            if case .creating(let task) = lazySender {
                return task
            }
            throw DiMLSError.sendGroupNotReady
        }
        let task = Task {
            do {
                let archive = try await createSendGroup(
                    myCredential: myCredential,
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
                        identityProvider: identityProvider
                    )
                )
            } catch {
                print("error creating: \(error)")
                lazySender = .queued
                throw error
            }
        }
        lazySender = .creating(task)
        return task
    }

    private func createSendGroup(
        myCredential: Credential,
        credentialFetcher: CredentialKeyPackageFetcher,
        referenceIdFetcher: ReferenceIdKeyPackageFetcher
    ) async throws -> Sender.Archive {
        if case .ready = lazySender {
            throw DiMLSError.disallowed
        }
        //capture a snapshot of what the group needs
        var remotes = [DiMLS.ReferenceID: SendChannelInputs<Credential>.Remote]()

        for member
            in totalGroup
            .membershipForCreating(sender: myCredential.referenceId)
        {
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
                diGroupID: totalGroup.diGroupId,
                myCredential: myCredential,
                remotes: remotes
            ),
            identityProvider: Sender.identityProvider(
                totalGroup: totalGroup,
                sender: myCredential
            )
        )
    }

    public func encryptWithCommits(
        plaintext: Data,
        authenticating: Data,
        staplingCommit: Bool
    ) throws -> [(Credential, DiMLS.EncryptOutput)] {
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
    ) throws -> DiMLS.CommitEffect<Credential>? {
        guard pendingState.commitNeeded else {
            return nil
        }

        let input = try prepareCommit()

        return try commit(input: input, sender: sender)

        throw DiMLSError.notImplemented
    }

    private func commit(
        input: DiMLS.CommitInput<Credential>,
        sender: Sender,
    ) throws -> DiMLS.CommitEffect<Credential> {
        var newRemotes: [DiMLS.CredentialedKeyPackage<Credential>] = []

        //modify remotes and group
        for action in input.proposals {
            switch action {
            case .add(let credentialKeyPackage):
                newRemotes.append(credentialKeyPackage)
                //have to add to the total group that serves as a identity provider
                try totalGroup.add(member: credentialKeyPackage.credential)
            }
        }

        let sendChannel = try lazySender.readyChannel

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
}

//(Deprecate) full-featured compound api's
extension DiMLS.DiGroup {
    //    public func encryptWithCommits(
    //        plaintext: Data,
    //        authenticating: Data,
    //        staplingCommit: Bool
    //    ) throws -> [(Credential, DiMLS.EncryptOutput)] {
    //        //use the ratchet tree
    //        let privateMessage = try encrypt(
    //            plaintext: plaintext,
    //            authenticating: authenticating
    //        )
    //
    //        return try privateMessage.addressees.map { credential in
    //            guard let remoteState = remoteStates[credential.referenceId] else {
    //                throw DiMLSError.missingRemoteState
    //            }
    //
    //            return (
    //                credential,
    //                try remoteState.package(
    //                    privateMessage: privateMessage.body,
    //                    epoch: privateMessage.epoch,
    //                    staplingCommit: staplingCommit
    //                )
    //            )
    //        }
    //    }

    //    public func received(welcome: WelcomeOutput) throws {
    //        guard welcome.diGroupId == totalGroup.diGroupId else {
    //            throw DiMLSError.mismatchedGroupId
    //        }
    //
    //        let senderReferenceId = try welcome.senderReferenceId
    //
    //        //is this a member of the group?
    //        if totalGroup.members.contains(senderReferenceId) {
    //            try expectedMember(welcome: welcome)
    //        } else {
    //            try newMember(welcome: welcome)
    //        }
    //
    //        //is this a
    //    }

    private func newMember(welcome: WelcomeOutput) throws {
        let senderReferenceId = try welcome.senderReferenceId
        assert(!totalGroup.members.keys.contains(senderReferenceId))

        guard totalGroup.canAdd(try welcome.senderReferenceId) == nil else {
            throw DiMLSError.duplicateSendGroup
        }
        throw DiMLSError.notImplemented
    }

    //    private func expectedMember(welcome: WelcomeOutput) throws {
    //        let senderReferenceId = try welcome.senderReferenceId
    //        assert(totalGroup.members.contains(senderReferenceId))
    //
    //        //where do I process this new welcome?
    //        //do I already have a sendgroup for this sender?
    //        if let remoteState = remoteStates[senderReferenceId] {
    //            guard !remoteState.receivedWelcome else {
    //                throw DiMLSError.duplicateSendGroup
    //            }
    //            //can setup the remoteSTate
    //        } else {
    //
    //        }
    //    }
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

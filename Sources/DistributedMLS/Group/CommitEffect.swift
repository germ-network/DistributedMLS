//
//  CommitEffect.swift
//  DiMLS
//
//  Created by Mark @ Germ on 1/10/26.
//

extension DiMLS {
    public struct EncryptResult<C: DiMLSCredential> {
        let privateMessage: PrivateMessage<C>
        //application messages always follow a commit. let the application
        let commitEffect: CommitEffect<C>?
    }

    public struct CommitEffect<C: DiMLSCredential> {
        let didIntroduceNewPubKey: Bool
        let localOps: [DiMLSOperations<C>]
        //need to annotate the causal dependencies as well
        let followOps: [DiMLSOperations<C>]
        let dependencies: [ReferenceID: UInt64]
    }
}

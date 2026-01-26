//
//  WelcomeOutputInterface.swift
//  DiMLS
//
//  Created by Mark @ Germ on 1/4/26.
//

import Foundation

public protocol WelcomeOutputInterface: Sendable {
    associatedtype Credential: DiMLSCredential
    var diGroupId: Data { get }
    var senderReferenceId: DiMLS.ReferenceID { get throws }
    var keyedDependency: DiMLS.KeyedDependency? { get }
    var appPrivateMessage: Data? { get }
    func membershipEpoch(myCredential: Credential) throws
        -> DiMLS.TotalGroup<Credential>.Membership.Epoch
}

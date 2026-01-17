//
//  Client.swift
//  DiMLS
//
//  Created by Mark @ Germ on 12/8/25.
//

import Foundation

extension DiMLS {
    public protocol Client: Actor, Archivable {
        associatedtype Credential: DiMLSCredential
        associatedtype Invitation: DiInvitation  //where Invitation.Credential == Credential
        associatedtype Group: DiGroup where Group.WelcomeOutput == WelcomeOutput
        associatedtype WelcomeOutput: WelcomeOutputInterface
        where
            Group.Credential == Credential
        //            Invitation.WelcomeOutput == WelcomeOutput

        static func create(credential: Credential) throws -> Self

        var archive: Archive { get throws }
        var credential: Credential { get }

        var currentKeyPackage:
            (
                keyPackageId: Data,
                keyPackage: CredentialedKeyPackage<Credential>
            )
        { get throws }

        func createGroup(diGroupId: Data?) throws -> Group

        func create(
            receivedGroup: WelcomeOutput,
            keyPackages: [ReferenceID: Data],
        ) throws -> Group

        func process(
            wireWelcome: Data,
            keyPackageId: KeyPackageId?
        ) throws -> (
            KeyPackageId,
            WelcomeOutput
        )
    }
}

public protocol Archivable {
    associatedtype Archive: Sendable, Codable
    init(archive: Archive) throws

    //helps to define this in the protocol for Actor protocols
    //    var archive: Archive { get throws }
}

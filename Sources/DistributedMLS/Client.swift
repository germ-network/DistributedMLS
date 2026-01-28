//
//  Client.swift
//  DiMLS
//
//  Created by Mark @ Germ on 12/8/25.
//

import Foundation

extension DiMLS {
    public protocol Client: Archivable {
        associatedtype Credential: DiMLSCredential
        associatedtype Group: DiGroup
        where Group.Receiver.WelcomeOutput == WelcomeOutput, Group.Credential == Credential
        associatedtype WelcomeOutput: WelcomeOutputInterface

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
            keyPackageId: KeyPackageId?,
            knownDependencies: [DiMLS.KeyedDependency]
        ) throws -> (
            KeyPackageId,
            WelcomeOutput
        )
    }
}

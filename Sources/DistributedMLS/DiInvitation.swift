//
//  DiInvitation.swift
//  DiMLS
//
//  Created by Mark @ Germ on 1/4/26.
//

import Foundation

///An invitation is a logical entity that can be added to DiGroups
extension DiMLS {
    public typealias KeyPackageId = Data
    public protocol DiInvitation: Archivable {
        //        associatedtype Credential: DiMLSCredential
        //        associatedtype WelcomeOutput

        var currentKeyPackage: (keyPackageId: Data, keyPackageMessage: Data) { get throws }

        ///returns an atomic group (archive)
        ///the application determines which DiGroup it should belong to based
        ///on the resulting group's groupId
        //        func process(mlsWelcome: Data, keyPackageId: KeyPackageId?) throws -> (
        //            KeyPackageId,
        //            WelcomeOutput
        //        )
    }
}

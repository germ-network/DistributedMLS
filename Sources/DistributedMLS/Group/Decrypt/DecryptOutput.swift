//
//  DecryptOutput.swift
//  DistributedMLS
//
//  Created by Mark @ Germ on 1/19/26.
//

import Foundation

extension DiMLS {
    public struct DecryptOutput<C: DiMLSCredential>: Sendable {
        public let appPlaintext: AppPlaintext
        public let commitResult: CommitResult<C>?

        public init(
            appPlaintext: AppPlaintext,
            commitResult: CommitResult<C>?
        ) {
            self.appPlaintext = appPlaintext
            self.commitResult = commitResult
        }
    }

    public struct CommitResult<C: DiMLSCredential>: Sendable {
        public let added: [C]
        let keyedDependency: KeyedDependency
        public init(added: [C], keyedDependency: KeyedDependency) {
            self.added = added
            self.keyedDependency = keyedDependency
        }
    }

    public struct AppPlaintext: Sendable, Equatable {
        public let application: Data
        public let authenticating: Data
        public let sender: Data

        public init(application: Data, authenticating: Data, sender: Data) {
            self.application = application
            self.authenticating = authenticating
            self.sender = sender
        }
    }
}

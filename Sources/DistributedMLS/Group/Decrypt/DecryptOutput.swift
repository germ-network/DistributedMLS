//
//  DecryptOutput.swift
//  DistributedMLS
//
//  Created by Mark @ Germ on 1/19/26.
//

import Foundation

extension DiMLS {
    public struct DecryptOutput: Sendable {
        public let appPlaintext: AppPlaintext
        public let commitResult: CommitResult?

        public init(
            appPlaintext: AppPlaintext,
            commitResult: CommitResult?
        ) {
            self.appPlaintext = appPlaintext
            self.commitResult = commitResult
        }
    }

    public struct CommitResult: Sendable {

        public init() {

        }
    }

    public struct AppPlaintext: Sendable, Equatable {
        public let application: Data
        public let authenticating: Data

        public init(application: Data, authenticating: Data) {
            self.application = application
            self.authenticating = authenticating
        }
    }
}

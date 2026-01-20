//
//  DecryptOutput.swift
//  DistributedMLS
//
//  Created by Mark @ Germ on 1/19/26.
//

import Foundation

extension DiMLS {
    public struct DecryptOutput: Sendable {
        let appPlaintext: AppPlaintext
        let controlMessage: ControlMessage?
    }

    public struct ControlMessage: Sendable {

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

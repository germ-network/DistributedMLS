//
//  ReceiveChannel.swift
//  DiMLS
//
//  Created by Mark @ Germ on 1/6/26.
//

import Foundation

public protocol ReceiveChannel {
    associatedtype WelcomeOutput: WelcomeOutputInterface
    static func create(welcome: WelcomeOutput) throws -> Self
    func decrypt(messageData: Data) throws -> DiMLS.AppPlaintext
}

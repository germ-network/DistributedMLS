//
//  WireInterfaces.swift
//  DiMLS
//
//  Created by Mark @ Germ on 12/31/25.
//

import Foundation

///Interfaces for DiGroup wireformats

public protocol DiControlMessage: Sendable, Archivable {
    associatedtype Welcome: DiWelcome
    associatedtype Commit: DiCommit

    var asCommit: Commit? { get }
    var asWelcome: Welcome? { get }
    var epoch: UInt64 { get }
}

public protocol DiWelcome: Sendable, Archivable {
    //should hold onto init key of the recipent for header encryption
    var recipientInitKeyData: Data { get }
    var epoch: UInt64 { get }
}

public protocol DiCommit: Sendable, Archivable {
    var epoch: UInt64 { get }
}

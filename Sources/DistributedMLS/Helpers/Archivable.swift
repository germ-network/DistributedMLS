//
//  Archivable.swift
//  DistributedMLS
//
//  Created by Mark @ Germ on 1/17/26.
//

public protocol Archivable {
    associatedtype Archive: Sendable, Codable
    init(archive: Archive) throws

    //helps to define this in the protocol for Actor protocols
    //    var archive: Archive { get throws }
}

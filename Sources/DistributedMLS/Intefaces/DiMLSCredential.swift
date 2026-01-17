//
//  DiMLSCredential.swift
//  DiMLS
//
//  Created by Mark @ Germ on 11/30/25.
//

import Foundation

///we use the basic credential configuration of MLS
public protocol DiMLSCredential: Hashable, Sendable {
    var referenceId: Data { get }
    //for filling the basic credential field.
    var encoded: Data { get }

    init(encoded: Data) throws
}

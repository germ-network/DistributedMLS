//
//  Participant.swift
//  DiMLS
//
//  Created by Mark @ Germ on 1/7/26.
//

import Foundation

//exists for clients to reason about which credential to point to
extension DiMLS {
    public enum Participant<Credential: DiMLSCredential> {
        case credential(Credential, DiMLS.EpochID)
        case referenceId(DiMLS.ReferenceID)
    }
}

//
//  OutputStream.swift
//  BodyDetectionBroadcasting
//
//  Created by Michael A Edgcumbe on 2/13/24.
//

import Foundation

extension OutputStream {
    func write(_ data: Data) -> Int {
        return data.withUnsafeBytes({ (rawBufferPointer: UnsafeRawBufferPointer) -> Int in
            let bufferPointer = rawBufferPointer.bindMemory(to: UInt8.self)
            return self.write(bufferPointer.baseAddress!, maxLength: data.count)
        })
    }
}

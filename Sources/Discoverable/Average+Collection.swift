//
//  Array+Average.swift
//  Assistive Technology
//
//  Created by Ben Mechen on 05/02/2020.
//  Copyright © 2020 Team 30. All rights reserved.
//

import Foundation


extension Collection where Element == Float, Index == Int {
    /// Return the mean of a list of Floats
    var average: Float? {
        guard !isEmpty else {
            return nil
        }
        
        let sum = reduce(Float(0)) { current, next -> Float in
            return current + next
        }
        
        return sum / Float(count)
    }
}


//
//  Result.swift
//  Assistive Technology
//
//  Created by Ben Mechen on 29/01/2020.
//  Copyright © 2020 Team 30. All rights reserved.
//

import Foundation

enum Result<T> {
  case success(T)
  case error(Error)
}

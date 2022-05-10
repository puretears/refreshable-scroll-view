//
//  File.swift
//  
//
//  Created by Mars on 2022/5/6.
//

import SwiftUI
import Foundation

enum ViewType: Int {
  case movingView
  case fixedView
  case contentView
}

struct TopPrefData: Equatable {
  let vType: ViewType
  let bound: CGRect
}

struct TopPrefKey: PreferenceKey {
  static var defaultValue: [TopPrefData] = []
  
  static func reduce(value: inout [TopPrefData], nextValue: () -> [TopPrefData]) {
    value.append(contentsOf: nextValue())
  }
}

struct ContentPrefData {
  let vType: ViewType
  let bound: Anchor<CGRect>
}

struct ContentPrefKey: PreferenceKey {
  static var defaultValue: [ContentPrefData] = []
  
  static func reduce(value: inout [ContentPrefData], nextValue: () -> [ContentPrefData]) {
    value.append(contentsOf: nextValue())
  }
}

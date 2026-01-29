//
//  Region.swift
//  QuickTrim
//

import Foundation

struct Region: Identifiable, Equatable {
    let id = UUID()
    var startTime: Double
    var endTime: Double
    var isBinned: Bool = false

    var duration: Double {
        endTime - startTime
    }

    func contains(time: Double) -> Bool {
        time >= startTime && time < endTime
    }

    var middleTime: Double {
        (startTime + endTime) / 2
    }
}

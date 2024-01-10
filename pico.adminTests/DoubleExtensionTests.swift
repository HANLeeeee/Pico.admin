//
//  pico_adminTests.swift
//  pico.adminTests
//
//  Created by 최하늘 on 12/8/23.
//

import XCTest
@testable import Pico_admin

final class DoubleExtensionTests: XCTestCase {
    var sut: Double?

    override func setUpWithError() throws {
        sut = Date().timeIntervalSince1970
    }

    override func tearDownWithError() throws {
        sut = nil
    }

    func test_DoubleToString_Date타입의_Double타입을_yyyy_dash_mm_dash_dd_형태로_변경하기() throws {
        var result = ""
        result = sut!.toString(dateSeparator: .dash)
        
        XCTAssertEqual(result, "2024-01-10")
        assert(true, "test_DoubleToString_Date타입의_Double타입을_yyyy_dash_mm_dash_dd_형태로_변경하기 ====> true")
    }
    
    func test_DoubleToString_Date타입의_Double타입을_yyyy_dot_mm_dot_dd_형태로_변경하기() throws {
        var result = ""
        result = sut!.toString(dateSeparator: .dot)
        
        XCTAssertEqual(result, "2024.01.10")
        assert(true, "test_DoubleToString_Date타입의_Double타입을_yyyy_dot_mm_dot_dd_형태로_변경하기 ====> true")
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }
}

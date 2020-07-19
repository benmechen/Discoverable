import XCTest

import DiscoverableTests

var tests = [XCTestCaseEntry]()
tests += DiscoverableTests.allTests()
XCTMain(tests)

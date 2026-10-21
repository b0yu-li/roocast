import XCTest
@testable import Roocast

final class CalculatorTests: XCTestCase {

    func testBasicArithmetic() {
        XCTAssertEqual(Calculator.evaluate("2+2")?.copyText, "4")
        XCTAssertEqual(Calculator.evaluate("10 - 3")?.copyText, "7")
        XCTAssertEqual(Calculator.evaluate("3*4")?.copyText, "12")
        XCTAssertEqual(Calculator.evaluate("8/2")?.copyText, "4")
        XCTAssertEqual(Calculator.evaluate("2^10")?.copyText, "1024")
        XCTAssertEqual(Calculator.evaluate("2**3")?.copyText, "8")
    }

    func testPrecedenceAndGrouping() {
        XCTAssertEqual(Calculator.evaluate("2+3*4")?.copyText, "14")
        XCTAssertEqual(Calculator.evaluate("(2+3)*4")?.copyText, "20")
        XCTAssertEqual(Calculator.evaluate("-(2+3)")?.copyText, "-5")
    }

    func testFunctionsAndConstants() {
        XCTAssertEqual(Calculator.evaluate("sqrt(9)")?.copyText, "3")
        XCTAssertEqual(Calculator.evaluate("abs(-7)")?.copyText, "7")
        XCTAssertEqual(Calculator.evaluate("2*pi")?.copyText, Calculator.evaluate("2*π")?.copyText)
        XCTAssertEqual(Calculator.evaluate("min(3,1,2)")?.copyText, "1")
        XCTAssertEqual(Calculator.evaluate("max(3,1,2)")?.copyText, "3")
        XCTAssertEqual(Calculator.evaluate("pow(2,3)")?.copyText, "8")
    }

    func testPercent() {
        XCTAssertEqual(Calculator.evaluate("100+10%")?.copyText, "110")
        XCTAssertEqual(Calculator.evaluate("100-10%")?.copyText, "90")
        XCTAssertEqual(Calculator.evaluate("10% of 50")?.copyText, "5")
        // Bare percent is not a calculation — stay out of the way of app search.
        XCTAssertNil(Calculator.evaluate("50%"))
    }

    func testFactorialAndCompact() {
        XCTAssertEqual(Calculator.evaluate("5!")?.copyText, "120")
        XCTAssertEqual(Calculator.evaluate("10k")?.copyText, "10000")
        XCTAssertEqual(Calculator.evaluate("10k + 1")?.copyText, "10001")
    }

    func testRadixAndTrailingEquals() {
        XCTAssertEqual(Calculator.evaluate("0xff")?.copyText, "255")
        XCTAssertEqual(Calculator.evaluate("0b1010")?.copyText, "10")
        XCTAssertEqual(Calculator.evaluate("2+2=")?.copyText, "4")
    }

    func testPartialTrailingOperator() {
        XCTAssertEqual(Calculator.evaluate("2+2+")?.copyText, "4")
        XCTAssertEqual(Calculator.evaluate("10*")?.copyText, "10")
    }

    func testLoneLiteralIsNotCalculator() {
        XCTAssertNil(Calculator.evaluate("42"))
        XCTAssertNil(Calculator.evaluate("pi"))
        XCTAssertNil(Calculator.evaluate(""))
        XCTAssertNil(Calculator.evaluate("notes"))
        XCTAssertNil(Calculator.evaluate("hello world"))
    }

    func testExpressionEchoUsesPrettyOperators() {
        XCTAssertEqual(Calculator.evaluate("2*3")?.expression, "2×3")
        XCTAssertEqual(Calculator.evaluate("8/2")?.expression, "8÷2")
    }

    func testGroupedDisplay() {
        XCTAssertEqual(Calculator.evaluate("1000*1000")?.display, "1,000,000")
        XCTAssertEqual(Calculator.evaluate("1000*1000")?.copyText, "1000000")
    }

    func testComparison() {
        XCTAssertEqual(Calculator.evaluate("1+1==2")?.copyText, "1")
        XCTAssertEqual(Calculator.evaluate("3>5")?.copyText, "0")
    }
}

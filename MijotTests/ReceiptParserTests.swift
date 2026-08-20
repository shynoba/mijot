import XCTest
@testable import Mijot

final class ReceiptParserTests: XCTestCase {
    func testParsesMeasuredProductAndRemovesPrice() throws {
        let line = try XCTUnwrap(ReceiptParser.parseLine("TOMATES GRAPPE 0,842 kg 3,49"))
        XCTAssertEqual(line.name, "Tomates Grappe")
        XCTAssertEqual(line.quantity, 842, accuracy: 0.01)
        XCTAssertEqual(line.unit, .gram)
    }

    func testParsesMultipack() throws {
        let line = try XCTUnwrap(ReceiptParser.parseLine("2 X YAOURT NATURE 1,98 €"))
        XCTAssertEqual(line.name, "Yaourt Nature")
        XCTAssertEqual(line.quantity, 2)
        XCTAssertEqual(line.unit, .piece)
    }

    func testIgnoresPaymentAndTotals() {
        XCTAssertNil(ReceiptParser.parseLine("TOTAL A PAYER 45,60 €"))
        XCTAssertNil(ReceiptParser.parseLine("CARTE BANCAIRE 45,60"))
    }

    func testUnitConversion() {
        XCTAssertEqual(UnitConverter.convert(1.5, from: .kilogram, to: .gram), 1500)
        XCTAssertEqual(UnitConverter.convert(75, from: .centiliter, to: .milliliter), 750)
    }

    func testDefaultMealCalendarTimes() {
        let preferences = CalendarPreferences()
        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 20))!
        let lunch = Calendar.current.dateComponents([.hour, .minute], from: preferences.date(on: day, for: .lunch))
        let dinner = Calendar.current.dateComponents([.hour, .minute], from: preferences.date(on: day, for: .dinner))

        XCTAssertEqual(lunch.hour, 12)
        XCTAssertEqual(lunch.minute, 30)
        XCTAssertEqual(dinner.hour, 19)
        XCTAssertEqual(dinner.minute, 30)
    }

    func testCustomMealCalendarTime() {
        var preferences = CalendarPreferences()
        let customTime = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 13, minute: 15))!
        preferences.setTime(customTime, for: .lunch)

        XCTAssertEqual(preferences.lunchHour, 13)
        XCTAssertEqual(preferences.lunchMinute, 15)
    }

    func testRecipeCostUsesIngredientQuantityAndUnitConversion() {
        let stock = [
            StockItem(
                name: "Riz basmati",
                quantity: 1,
                unit: .kilogram,
                unitPrice: 3
            ),
            StockItem(
                name: "Poulet",
                quantity: 500,
                unit: .gram,
                unitPrice: 0.012
            )
        ]
        let recipe = Recipe(
            id: "cost-test",
            name: "Poulet riz",
            subtitle: "Test",
            symbol: "fork.knife",
            tintName: "black",
            durationMinutes: 20,
            baseServings: 1,
            ingredients: [
                RecipeIngredient("Riz", quantity: 100, unit: .gram),
                RecipeIngredient("Poulet", quantity: 150, unit: .gram)
            ],
            steps: []
        )

        let estimate = LocalRecipeEngine.costEstimate(for: recipe, stock: stock)
        XCTAssertEqual(estimate.knownCost, 2.10, accuracy: 0.001)
        XCTAssertTrue(estimate.isComplete)
    }
}

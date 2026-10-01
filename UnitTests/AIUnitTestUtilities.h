// XCTAssertEqual compares floating point values with ==, as STAssertEquals did. Every expected
// component and interval in these tests is either exactly representable (0, 0.25, 0.5, 0.75, 1)
// or computed the same way on both sides (127/255), so this tolerance only absorbs the rounding
// of a conversion, never a wrong value: one millionth is far below the 1/255 of an 8-bit colour step.
#define AIFloatComparisonAccuracy 0.000001

#define AISimplifiedAssertEqualObjects(objectToTest, objectToExpect, message) \
	XCTAssertEqualObjects((objectToTest), (objectToExpect), @"%s: %@: Expected %C%@%C; got %C%@%C", __PRETTY_FUNCTION__, message, /*open quote*/ 0x201C, (objectToExpect), /*close quote*/ 0x201D, /*open quote*/ 0x201C, (objectToTest), /*close quote*/ 0x201D);

import QtQuick
import QtTest
import "../SettingsSchema.js" as Schema

TestCase {
    name: "SettingsSchema"

    function test_missingEntryReadsFallbacks() {
        compare(Schema.read(null, "windowFooterStyle"), "floating");
        compare(Schema.read(null, "backgroundBlur"), 4);
        compare(Schema.read(null, "moveCursorToWindow"), true);
        compare(Schema.read(null, "hotCornerAllDisplays"), false);
    }

    function test_enumReadsListedValueOnly() {
        compare(Schema.read({windowFooterStyle: "integrated"}, "windowFooterStyle"), "integrated");
        compare(Schema.read({windowFooterStyle: "bogus"}, "windowFooterStyle"), "floating");
        compare(Schema.read({windowFooterStyle: ""}, "windowFooterStyle"), "floating");
    }

    function test_integerReadsClampAndRound() {
        compare(Schema.read({backgroundBlur: 99}, "backgroundBlur"), 20);
        compare(Schema.read({backgroundBlur: -3}, "backgroundBlur"), 0);
        compare(Schema.read({backgroundBlur: 7.6}, "backgroundBlur"), 8);
        compare(Schema.read({backgroundBlur: "x"}, "backgroundBlur"), 4);
        compare(Schema.read({backgroundBlur: null}, "backgroundBlur"), 4);
    }

    function test_booleanFallbackDecidesWhichValueCounts() {
        compare(Schema.read({moveCursorToWindow: "no"}, "moveCursorToWindow"), true);
        compare(Schema.read({moveCursorToWindow: false}, "moveCursorToWindow"), false);
        compare(Schema.read({hotCornerAllDisplays: "yes"}, "hotCornerAllDisplays"), false);
        compare(Schema.read({hotCornerAllDisplays: true}, "hotCornerAllDisplays"), true);
    }

    function test_normalizeInvalidIntegerKeepsCurrent() {
        compare(Schema.normalize("backgroundDim", "x", 33), 33);
        compare(Schema.normalize("backgroundDim", 120, 33), 90);
    }

    function test_normalizeEnumAndBoolean() {
        compare(Schema.normalize("previewPlacement", "centered", "in-place"), "centered");
        compare(Schema.normalize("previewPlacement", "middle", "centered"), "in-place");
        compare(Schema.normalize("showFooter", "true", true), false);
        compare(Schema.normalize("showFooter", true, false), true);
    }

    function test_expectedOneOfReadsNaturallyForOneTwoAndMany() {
        compare(Schema.expectedOneOf(["grid"]), "expected grid");
        compare(Schema.expectedOneOf(["on", "off"]), "expected on or off");
        compare(Schema.expectedOneOf(["a", "b", "c"]), "expected a, b, or c");
    }

    // The text scripts already rely on, from before the schema.
    function test_ipcErrorsNameTheOptions() {
        compare(Schema.parseIpc("previewPlacement", "x").error, "expected in-place or centered");
        compare(Schema.parseIpc("windowFooterStyle", "x").error, "expected floating, integrated, overlay, or centered");
        compare(Schema.parseIpc("multiMonitorMode", "x").error, "expected mirrored or per-monitor");
        compare(Schema.parseIpc("showFooter", "yes").error, "expected on or off");
        compare(Schema.parseIpc("showFooter", "off").value, false);
        compare(Schema.parseIpc("hotCornerPosition", "top-right").value, "top-right");
    }

    function test_unknownSettingThrowsNamingIt() {
        var message = "";
        try { Schema.read(null, "nope"); } catch (error) { message = String(error.message); }
        compare(message, "unknown setting nope");
    }
}

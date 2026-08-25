import QtQuick
import QtTest
import "../IconResolver.js" as IconResolver

TestCase {
    name: "IconResolver"

    readonly property var entries: [
        {id: "code", name: "Visual Studio Code", startupClass: "Code", icon: "vscode"},
        {id: "t3code", name: "T3 Code Nightly", startupClass: "t3code", icon: "t3code-nightly"},
        {id: "Carrier", name: "Carrier", startupClass: "carrier", icon: "carrier"},
        {id: "hidden-app", name: "Hidden App", startupClass: "hidden", icon: "hidden", noDisplay: true},
        {id: "first-chat", name: "Chat", startupClass: "", icon: "first-chat"},
        {id: "second-chat", name: "Chat", startupClass: "", icon: "second-chat"}
    ]

    function toplevel(appId, windowClass, initialClass) {
        return {
            wayland: {appId: appId},
            lastIpcObject: {class: windowClass, initialClass: initialClass}
        };
    }

    function test_collectsFullStableIdentity() {
        var identity = IconResolver.identityFor(toplevel("T3Code.desktop", "t3code", "T3CODE"));
        compare(identity.key, "t3code|t3code|t3code");
        compare(identity.candidates.length, 1);
        compare(identity.candidates[0], "t3code");
    }

    function test_exactIdDoesNotCollideWithSubstring() {
        var entry = IconResolver.findEntry(entries, ["t3code"]);
        verify(entry !== null);
        compare(entry.id, "t3code");
        compare(entry.icon, "t3code-nightly");
    }

    function test_matchesStartupClassCaseInsensitively() {
        var entry = IconResolver.findEntry(entries, ["CARRIER"]);
        verify(entry !== null);
        compare(entry.icon, "carrier");
    }

    function test_ignoresHiddenEntries() {
        compare(IconResolver.findEntry(entries, ["hidden-app"]), null);
    }

    function test_ambiguousNameDoesNotGuess() {
        compare(IconResolver.findEntry(entries, ["chat"]), null);
    }

    function test_usesClassWhenWaylandAppIdIsGeneric() {
        var identity = IconResolver.identityFor(toplevel("", "carrier", ""));
        var entry = IconResolver.findEntry(entries, identity.candidates);
        verify(entry !== null);
        compare(entry.id, "Carrier");
    }
}

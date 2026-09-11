import QtQuick
import QtTest
import "../WorkspaceModel.js" as WorkspaceModel

TestCase {
    name: "WorkspaceModel"

    function test_readsIdentity() {
        var workspace = {id: 2, name: "2"};

        compare(WorkspaceModel.idFor(workspace), 2);
        compare(WorkspaceModel.nameFor(workspace), "2");
        compare(WorkspaceModel.keyFor(workspace), "id:2");
        compare(WorkspaceModel.labelFor(workspace), "2");
        verify(WorkspaceModel.isNumbered(workspace));
    }

    function test_handlesMissingWorkspace() {
        compare(WorkspaceModel.idFor(null), 0);
        compare(WorkspaceModel.nameFor(null), "");
        compare(WorkspaceModel.keyFor(null), "");
        compare(WorkspaceModel.labelFor(null), "—");
        verify(!WorkspaceModel.isNumbered(null));
    }

    function test_namedWorkspaceUsesItsIdForIdentity() {
        var workspace = {id: -42, name: "Web"};

        compare(WorkspaceModel.keyFor(workspace), "id:-42");
        compare(WorkspaceModel.labelFor(workspace), "Web");
        verify(!WorkspaceModel.isNumbered(workspace));
    }

    function test_fallsBackToNameWithoutValidId() {
        var workspace = {name: "Web"};

        compare(WorkspaceModel.keyFor(workspace), "name:Web");
        compare(WorkspaceModel.labelFor(workspace), "Web");
    }

    function test_avoidsNumericNamedWorkspaceKeyCollision() {
        var numbered = {id: 1, name: "1"};
        var named = {id: -10, name: "1"};

        verify(WorkspaceModel.keyFor(numbered) !== WorkspaceModel.keyFor(named));
    }

    function test_sortsNumberedWorkspacesNumerically() {
        var source = [
            {id: 10, name: "10"},
            {id: 2, name: "2"},
            {id: 1, name: "1"}
        ];

        var result = WorkspaceModel.sorted(source);

        compare(WorkspaceModel.labelFor(result[0]), "1");
        compare(WorkspaceModel.labelFor(result[1]), "2");
        compare(WorkspaceModel.labelFor(result[2]), "10");
    }

    function test_placesNamedWorkspacesAfterNumberedOnes() {
        var source = [
            {id: -20, name: "Web"},
            {id: 3, name: "3"},
            {id: -10, name: "Code"},
            {id: 1, name: "1"}
        ];

        var result = WorkspaceModel.sorted(source);

        compare(WorkspaceModel.labelFor(result[0]), "1");
        compare(WorkspaceModel.labelFor(result[1]), "3");
        compare(WorkspaceModel.labelFor(result[2]), "Code");
        compare(WorkspaceModel.labelFor(result[3]), "Web");
    }

    function test_acceptsObjectModelStyleValuesProperty() {
        var source = {
            values: [
                {id: 3, name: "3"},
                {id: 1, name: "1"}
            ]
        };

        var result = WorkspaceModel.sorted(source);

        compare(result.length, 2);
        compare(WorkspaceModel.labelFor(result[0]), "1");
        compare(WorkspaceModel.labelFor(result[1]), "3");
    }

    function test_acceptsPlainArrayWithNativeValuesMethod() {
        var source = [
            {id: 3, name: "3"},
            {id: 1, name: "1"}
        ];

        verify(typeof source.values === "function");

        var result = WorkspaceModel.sorted(source);

        compare(result.length, 2);
        compare(WorkspaceModel.labelFor(result[0]), "1");
        compare(WorkspaceModel.labelFor(result[1]), "3");
    }

    function test_sortDoesNotMutateSource() {
        var source = [
            {id: 2, name: "2"},
            {id: 1, name: "1"}
        ];

        var result = WorkspaceModel.sorted(source);

        compare(WorkspaceModel.labelFor(source[0]), "2");
        compare(WorkspaceModel.labelFor(result[0]), "1");
        verify(result !== source);
    }
}

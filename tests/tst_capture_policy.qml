import QtQuick
import QtTest
import "../CapturePolicy.js" as CapturePolicy

TestCase {
    name: "CapturePolicy"

    function test_closedOrOutOfLayoutCaptureIsInactive() {
        verify(!CapturePolicy.active(false, false, true));
        verify(!CapturePolicy.active(true, false, false));
        verify(!CapturePolicy.live(false, true, false));
        verify(!CapturePolicy.live(true, false, false));
    }

    function test_liveModeStreamsOnlyVisibleWindows() {
        verify(CapturePolicy.active(true, false, true));
        verify(CapturePolicy.live(true, true, false));
    }

    function test_lowLoadModeKeepsVisibleCaptureStill() {
        verify(CapturePolicy.active(true, false, true));
        verify(!CapturePolicy.live(true, true, true));
    }

    function test_dismissalStopsLiveUpdatesButKeepsCaptureMounted() {
        var source = ({window: "example"});
        var active = CapturePolicy.active(false, true, true);
        var live = CapturePolicy.live(false, true, false);
        verify(active, "the capture stays active through the exit animation");
        verify(!live, "live updates stop when dismissal begins");
        verify(CapturePolicy.shouldCaptureStill(active, live, source));
    }

    function test_captureSourceIsReleasedWhenInactiveOrRestarting() {
        var source = ({window: "example"});
        compare(CapturePolicy.captureSource(false, false, source), null);
        compare(CapturePolicy.captureSource(true, true, source), null);
        compare(CapturePolicy.captureSource(true, false, source), source);
    }

    function test_stillFrameIsRequestedOnlyForActiveNonLiveSource() {
        var source = ({window: "example"});
        verify(CapturePolicy.shouldCaptureStill(true, false, source));
        verify(!CapturePolicy.shouldCaptureStill(true, true, source));
        verify(!CapturePolicy.shouldCaptureStill(false, false, source));
        verify(!CapturePolicy.shouldCaptureStill(true, false, null));
    }
}

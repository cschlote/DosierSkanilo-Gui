/** UI helpers for the periodic video preview progress timer. */
module ui.previewprogress;

import gstreamer.GStreamer : GstState;
import gstreamer.c.types : GstStateChangeReturn;

import ui.documenttab : DocumentTab;
import ui.mainsources : UiMainSource, scheduleUiTimeout;

/** Callbacks required by the preview progress timer. */
struct PreviewProgressCallbacks
{
    DocumentTab delegate() currentDocument;
    void delegate(DocumentTab) syncVideoPreviewPosition;
    void delegate(DocumentTab) syncVideoTrackSelectors;
    void delegate(DocumentTab, bool) syncVideoPlaybackButton;
}

/** Start the periodic preview progress timer used while the application is running.
 *
 * Params:
 *     callbacks = Accessors used to query the current document and synchronize
 *         preview playback state.
 * Returns: A repeating GTK timeout that keeps the preview UI in sync.
 * Throws: Timer creation failures may propagate.
 */
UiMainSource startPreviewProgressTimer(PreviewProgressCallbacks callbacks)
{
    return scheduleUiTimeout(250, {
        auto document = callbacks.currentDocument();
        if (document !is null && (document.selectedPreviewIsVideo || document.selectedPreviewIsAudio)
            && document.previewVideoPlayer !is null)
        {
            callbacks.syncVideoPreviewPosition(document);
            callbacks.syncVideoTrackSelectors(document);

            GstState state;
            GstState pending;
            if (document.previewVideoPlayer.getState(state, pending, 0) != GstStateChangeReturn.FAILURE)
            {
                callbacks.syncVideoPlaybackButton(document, state == GstState.PLAYING);
            }
        }
        return true;
    });
}

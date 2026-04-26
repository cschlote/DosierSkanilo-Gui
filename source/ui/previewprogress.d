/** UI helpers for the periodic video preview progress timer. */
module ui.previewprogress;

import glib.Timeout;
import gstreamer.GStreamer : GstState;
import gstreamer.c.types : GstStateChangeReturn;

import ui.documenttab : DocumentTab;

/** Callbacks required by the preview progress timer. */
struct PreviewProgressCallbacks
{
    DocumentTab delegate() currentDocument;
    void delegate(DocumentTab) syncVideoPreviewPosition;
    void delegate(DocumentTab) syncVideoTrackSelectors;
    void delegate(DocumentTab, bool) syncVideoPlaybackButton;
}

/** Start the periodic preview progress timer used while the application is running. */
Timeout startPreviewProgressTimer(PreviewProgressCallbacks callbacks)
{
    return new Timeout(250, {
        auto document = callbacks.currentDocument();
        if (document !is null && document.selectedPreviewIsVideo && document.previewVideoPlayer !is null)
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
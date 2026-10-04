/** UI loader and signal wiring for the detail preview layout. */
module ui.detailpreview;

import gtk.AspectFrame;
import gtk.Box;
import gtk.Button;
import gtk.CheckButton;
import gtk.ComboBoxText;
import gtk.DrawingArea;
import gtk.Image;
import gtk.Label;
import gtk.ScrolledWindow;
import gtk.Scale;
import gtk.ToggleButton;
import gtk.Builder;
import gtk.Range;
import gtk.Widget;
import gobject.Value;
import gstreamer.c.types : GstState, GstStateChangeReturn;

import ui.builderutils : builderObject, loadUiBuilder;
import ui.documenttab : DocumentTab, PreviewScaleMode;
import ui.detailswidgets : jumpVideoPreview, pauseVideoPreview, playVideoPreview,
    refreshMediaPreview, resumePendingVideoPreview, seekVideoPreview,
    setElementIntProperty, setVideoPreviewVolume, syncVideoPreviewPosition,
    syncVideoPreviewWindow;

/** Widgets from the detail preview layout. */
struct DetailPreviewUi
{
    Box previewPane;
}

/** Callbacks needed to wire detail preview UI signals. */
struct DetailPreviewCallbacks
{
    bool delegate() isSyncingToolbarState;
    void delegate(PreviewScaleMode) setPreviewScaleMode;
    void delegate() syncPreviewToolbarFromCurrentDocument;
    void delegate(bool) setPreviewVideoAutostart;
    void delegate(double) setPreviewVideoVolume;
}

/** Bind the detail preview layout to a document tab.
 *
 * Params:
 *     document = Active document tab that receives the preview widgets.
 * Returns: A struct with the preview pane widgets.
 * Throws: Any missing builder object or GtkBuilder parse failure is propagated.
 */
DetailPreviewUi loadDetailPreviewUi(DocumentTab document)
{
    auto previewBuilder = loadUiBuilder!"source/ui/detailpreview.ui"("preview");
    document.previewBuilder = previewBuilder;

    DetailPreviewUi ui;
    ui.previewPane = builderObject!Box(previewBuilder, "preview", "previewPane");
    document.detailPreviewTitle = builderObject!Label(previewBuilder, "preview", "detailPreviewTitle");
    document.detailPreviewSummary = builderObject!Label(previewBuilder, "preview", "detailPreviewSummary");
    document.detailPreviewSummaryScroll = builderObject!ScrolledWindow(previewBuilder,
        "preview", "detailPreviewSummaryScroll");
    document.detailPreviewSummary.setXalign(0);
    document.detailPreviewSummary.setYalign(0);
    document.detailPreviewImageControls = builderObject!Box(previewBuilder, "preview", "previewControls");
    document.detailPreviewScroll = builderObject!ScrolledWindow(previewBuilder, "preview", "detailPreviewScroll");
    document.detailPreviewImage = builderObject!Image(previewBuilder, "preview", "detailPreviewImage");
    document.detailPreviewVideoFrame = builderObject!AspectFrame(previewBuilder, "preview", "detailPreviewVideoFrame");
    document.detailPreviewVideoArea = builderObject!DrawingArea(previewBuilder, "preview", "detailPreviewVideoArea");
    document.detailPreviewVideoControls = builderObject!Box(previewBuilder, "preview", "detailPreviewVideoControls");

    document.detailPreviewAutostartButton = builderObject!CheckButton(previewBuilder, "preview", "detailPreviewAutostartButton");
    document.detailPreviewJumpBackButton = builderObject!Button(previewBuilder, "preview", "detailPreviewJumpBackButton");
    document.detailPreviewPlayButton = builderObject!Button(previewBuilder, "preview", "detailPreviewPlayButton");
    document.detailPreviewJumpForwardButton = builderObject!Button(previewBuilder, "preview", "detailPreviewJumpForwardButton");
    document.detailPreviewPositionLabel = builderObject!Label(previewBuilder, "preview", "detailPreviewPositionLabel");
    document.detailPreviewPositionScale = builderObject!Scale(previewBuilder, "preview", "detailPreviewPositionScale");
    document.detailPreviewVolumeScale = builderObject!Scale(previewBuilder, "preview", "detailPreviewVolumeScale");
    document.detailPreviewTrackSelectorsRow = builderObject!Box(previewBuilder, "preview", "detailPreviewTrackSelectorsRow");
    document.detailPreviewVideoTrackBox = builderObject!Box(previewBuilder, "preview", "detailPreviewVideoTrackBox");
    document.detailPreviewAudioTrackBox = builderObject!Box(previewBuilder, "preview", "detailPreviewAudioTrackBox");
    document.detailPreviewSubtitleTrackBox = builderObject!Box(previewBuilder, "preview", "detailPreviewSubtitleTrackBox");
    document.detailPreviewVideoTrackCombo = builderObject!ComboBoxText(previewBuilder, "preview", "detailPreviewVideoTrackCombo");
    document.detailPreviewAudioTrackCombo = builderObject!ComboBoxText(previewBuilder, "preview", "detailPreviewAudioTrackCombo");
    document.detailPreviewSubtitleTrackCombo = builderObject!ComboBoxText(previewBuilder, "preview", "detailPreviewSubtitleTrackCombo");
    document.detailPreviewContainButton = builderObject!ToggleButton(previewBuilder, "preview", "detailPreviewContainButton");
    document.detailPreviewFitWidthButton = builderObject!ToggleButton(previewBuilder, "preview", "detailPreviewFitWidthButton");
    document.detailPreviewFitHeightButton = builderObject!ToggleButton(previewBuilder, "preview", "detailPreviewFitHeightButton");
    document.detailPreviewCenterButton = builderObject!ToggleButton(previewBuilder, "preview", "detailPreviewCenterButton");
    document.detailPreviewCoverButton = builderObject!ToggleButton(previewBuilder, "preview", "detailPreviewCoverButton");

    initializeDetailPreviewVolume(document);

    return ui;
}

/** Configure the preview volume slider and apply the document's current volume.
 *
 * Params:
 *     document = Active document tab whose volume widget should be initialized.
 * Returns: Nothing.
 * Throws: None.
 */
private void initializeDetailPreviewVolume(DocumentTab document)
{
    if (document.detailPreviewVolumeScale is null)
    {
        return;
    }

    document.detailPreviewVolumeScale.setRange(0.0, 1.0);
    document.detailPreviewVolumeScale.setIncrements(0.01, 0.10);
    setVideoPreviewVolume(document, document.previewVideoVolume);
    document.detailPreviewVolumeScale.setValue(document.previewVideoVolume);
}

/** Wire the preview controls and preview area behavior.
 *
 * Params:
 *     document = Active document tab that owns the preview widgets.
 *     callbacks = Toolbar synchronization hooks used by the preview controls.
 * Returns: Nothing.
 * Throws: None.
 */
void bindDetailPreviewSignals(DocumentTab document, DetailPreviewCallbacks callbacks)
{
    document.detailPreviewAutostartButton.setActive(document.previewVideoAutostart);
    document.detailPreviewAutostartButton.addOnToggled((ToggleButton button) {
        if (callbacks.isSyncingToolbarState())
        {
            return;
        }

        document.previewVideoAutostart = button.getActive();
        callbacks.setPreviewVideoAutostart(document.previewVideoAutostart);

        if (!document.selectedPreviewIsVideo && !document.selectedPreviewIsAudio)
        {
            return;
        }

        if (document.previewVideoAutostart)
        {
            playVideoPreview(document);
        }
        else
        {
            pauseVideoPreview(document);
        }
    });
    document.detailPreviewJumpBackButton.addOnClicked((Button _) {
        jumpVideoPreview(document, -10);
    });

    document.detailPreviewPlayButton.addOnClicked((Button _) {
        if (document.previewVideoPlayer is null)
        {
            playVideoPreview(document);
            return;
        }

        GstState state;
        GstState pending;
        auto stateResult = document.previewVideoPlayer.getState(state, pending, 0);
        if (stateResult == GstStateChangeReturn.FAILURE || state == GstState.NULL)
        {
            playVideoPreview(document);
            return;
        }

        if (state == GstState.PLAYING)
        {
            pauseVideoPreview(document);
        }
        else
        {
            playVideoPreview(document);
        }
    });

    document.detailPreviewJumpForwardButton.addOnClicked((Button _) {
        jumpVideoPreview(document, 10);
    });

    document.detailPreviewVideoTrackCombo.addOnChanged((ComboBoxText combo) {
        if (callbacks.isSyncingToolbarState() || document.previewVideoTrackSyncing || document.previewVideoPlayer is null)
        {
            return;
        }

        auto active = combo.getActive();
        if (active >= 0)
        {
            document.previewVideoPlayer.setProperty("current-video", new Value(active));
        }
    });
    document.detailPreviewAudioTrackCombo.addOnChanged((ComboBoxText combo) {
        if (callbacks.isSyncingToolbarState() || document.previewVideoTrackSyncing || document.previewVideoPlayer is null)
        {
            return;
        }

        auto active = combo.getActive();
        if (active >= 0)
        {
            document.previewVideoPlayer.setProperty("current-audio", new Value(active));
        }
    });
    document.detailPreviewSubtitleTrackCombo.addOnChanged((ComboBoxText combo) {
        if (callbacks.isSyncingToolbarState() || document.previewVideoTrackSyncing || document.previewVideoPlayer is null)
        {
            return;
        }

        auto active = combo.getActive();
        if (active >= 0)
        {
            setElementIntProperty(document.previewVideoPlayer, "current-text", active - 1);
        }
    });

    document.detailPreviewPositionScale.addOnValueChanged((Range range) {
        if (callbacks.isSyncingToolbarState() || document.previewVideoPositionSyncing)
        {
            return;
        }

        if (!seekVideoPreview(document, range.getValue()))
        {
            return;
        }

        syncVideoPreviewPosition(document);
    });

    document.detailPreviewVolumeScale.addOnValueChanged((Range range) {
        if (callbacks.isSyncingToolbarState())
        {
            return;
        }

        setVideoPreviewVolume(document, range.getValue());
        callbacks.setPreviewVideoVolume(document.previewVideoVolume);
    });

    document.detailPreviewScroll.addOnSizeAllocate((allocation, Widget _) {
        if (document.selectedPreviewPath.length == 0 || !document.selectedPreviewIsImage)
        {
            return;
        }
        refreshMediaPreview(document);
    });

    document.detailPreviewVideoArea.addOnRealize((Widget _) {
        syncVideoPreviewWindow(document);
        if (document.previewVideoPendingWindowSync)
            resumePendingVideoPreview(document);
        else if (document.selectedPreviewIsVideo)
        {
            refreshMediaPreview(document);
        }
    });

    document.detailPreviewVideoArea.addOnSizeAllocate((allocation, Widget _) {
        if (document.selectedPreviewIsVideo)
        {
            if (document.previewVideoPendingWindowSync)
                resumePendingVideoPreview(document);
            else
                syncVideoPreviewWindow(document, allocation.width, allocation.height);
        }
    });

    document.detailPreviewVideoFrame.addOnSizeAllocate((allocation, Widget _) {
        if (document.previewVideoPendingWindowSync)
            resumePendingVideoPreview(document);
    });

    document.detailPreviewContainButton.addOnToggled((ToggleButton button) {
        if (callbacks.isSyncingToolbarState() || !button.getActive())
        {
            return;
        }
        callbacks.setPreviewScaleMode(PreviewScaleMode.contain);
        callbacks.syncPreviewToolbarFromCurrentDocument();
    });
    document.detailPreviewFitWidthButton.addOnToggled((ToggleButton button) {
        if (callbacks.isSyncingToolbarState() || !button.getActive())
        {
            return;
        }
        callbacks.setPreviewScaleMode(PreviewScaleMode.fitWidth);
        callbacks.syncPreviewToolbarFromCurrentDocument();
    });
    document.detailPreviewFitHeightButton.addOnToggled((ToggleButton button) {
        if (callbacks.isSyncingToolbarState() || !button.getActive())
        {
            return;
        }
        callbacks.setPreviewScaleMode(PreviewScaleMode.fitHeight);
        callbacks.syncPreviewToolbarFromCurrentDocument();
    });
    document.detailPreviewCenterButton.addOnToggled((ToggleButton button) {
        if (callbacks.isSyncingToolbarState() || !button.getActive())
        {
            return;
        }
        callbacks.setPreviewScaleMode(PreviewScaleMode.center);
        callbacks.syncPreviewToolbarFromCurrentDocument();
    });
    document.detailPreviewCoverButton.addOnToggled((ToggleButton button) {
        if (callbacks.isSyncingToolbarState() || !button.getActive())
        {
            return;
        }
        callbacks.setPreviewScaleMode(PreviewScaleMode.cover);
        callbacks.syncPreviewToolbarFromCurrentDocument();
    });
}

/** UI helpers for loading-state feedback and progress phases. */
module ui.loadingstatus;

import glib.Timeout;
import gtk.ProgressBar;
import gtk.Spinner;

import ui.documenttab : DocumentTab;

/** Callbacks and widget hooks required to publish loading feedback. */
struct LoadingStatusCallbacks
{
    bool delegate() isLoading;
    void delegate(bool) setIsLoading;
    DocumentTab delegate() busyDocument;
    void delegate(DocumentTab) setBusyDocument;
    Timeout delegate() progressPulseTimer;
    void delegate(Timeout) setProgressPulseTimer;
    void delegate() syncToolbarSensitivity;
    void delegate(DocumentTab, bool) setTableColumnsResizable;
}

/** Publish a global busy state while a tab-specific worker is active. */
void setLoadingState(
    LoadingStatusCallbacks callbacks,
    DocumentTab document,
    bool loading,
    Spinner loadSpinner,
    ProgressBar progressBar,
    string message = ""
)
{
    callbacks.setIsLoading(loading);
    callbacks.setBusyDocument(loading ? document : null);
    callbacks.syncToolbarSensitivity();

    // Spalten bleiben nicht-resizable, damit die gemessenen Breiten stabil bleiben.
    callbacks.setTableColumnsResizable(document, false);

    if (loading)
    {
        loadSpinner.setVisible(true);
        loadSpinner.start();
        progressBar.setVisible(true);
        auto loadingText = message.length > 0 ? message : "Loading...";
        progressBar.setText(loadingText);
        progressBar.pulse();
        if (callbacks.progressPulseTimer() is null)
        {
            callbacks.setProgressPulseTimer(new Timeout(120, {
                if (!callbacks.isLoading())
                {
                    return false;
                }
                progressBar.pulse();
                return true;
            }));
        }
        if (document !is null)
        {
            document.status.setText(loadingText);
            document.btnCopySha1.setSensitive(false);
            document.btnCopyFile.setSensitive(false);
            document.btnCopyDetails.setSensitive(false);
        }
        return;
    }

    loadSpinner.stop();
    loadSpinner.setVisible(false);
    if (callbacks.progressPulseTimer() !is null)
    {
        auto timer = callbacks.progressPulseTimer();
        timer.stop();
        callbacks.setProgressPulseTimer(null);
    }
    progressBar.setVisible(false);
    progressBar.setFraction(0.0);
    progressBar.setText("Idle");

    if (document !is null)
    {
        document.btnCopySha1.setSensitive(document.selectedSha1.length > 0);
        document.btnCopyFile.setSensitive(document.selectedFileName.length > 0);
        document.btnCopyDetails.setSensitive(document.selectedDetailsText.length > 0);
        if (message.length > 0)
        {
            document.status.setText(message);
        }
    }
}

/** Publish a load phase update onto the GTK main loop for a single document tab. */
void setLoadingPhase(
    LoadingStatusCallbacks callbacks,
    DocumentTab document,
    ulong expectedRequestId,
    ProgressBar progressBar,
    string phaseText
)
{
    new Timeout(0, {
        if (!callbacks.isLoading() || callbacks.busyDocument() !is document || expectedRequestId != document.loadRequestId)
        {
            return false;
        }

        document.status.setText(phaseText);
        progressBar.setText(phaseText);
        return false;
    });
}
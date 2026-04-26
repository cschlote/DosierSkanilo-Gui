/** Shared GtkBuilder helpers for UI module loaders and widget lookup. */
module ui.builderutils;

import gtk.Builder;

import std.format : format;

import cli.logging;

/** Load a GtkBuilder layout from an embedded UI resource.
 *
 * Params:
 *     builderLabel = Human-readable label used in log output and error
 *         messages.
 * Returns: A fully initialized Gtk.Builder instance populated from the
 *     embedded UI resource.
 * Throws: Any builder parsing or resource-loading failure is propagated.
 */
Builder loadUiBuilder(string uiResource)(string builderLabel)
{
    auto builder = new Builder();
    logLineVerbose("[ui] loading ", builderLabel, " builder");
    builder.addFromString(import(uiResource));
    logLineVerbose("[ui] ", builderLabel, " builder loaded, objects=", builder.getObjects().length);
    return builder;
}

/** Retrieve a typed object from a GtkBuilder layout.
 *
 * Params:
 *     builder = Builder that owns the widget object.
 *     builderLabel = Human-readable label used in log output and error
 *         messages.
 *     objectName = GtkBuilder object name to look up.
 * Returns: The requested object cast to the target type.
 * Throws: Exception when the named object cannot be found.
 */
T builderObject(T)(Builder builder, string builderLabel, string objectName)
{
    logLineVerbose("[ui] builder lookup start ", builderLabel, ".", objectName);
    auto object = builder.getObject(objectName);
    if (object is null)
    {
        auto objectCount = builder.getObjects().length;
        logLine("[ui] missing GtkBuilder object ", builderLabel, ".", objectName,
            " (objects=", objectCount, ")");
        throw new Exception(format("Missing GtkBuilder object: %s.%s", builderLabel, objectName));
    }

    logLineVerbose("[ui] builder lookup ok ", builderLabel, ".", objectName);

    return cast(T) object;
}

/** Retrieve a typed object from a GtkBuilder layout, or return null if missing.
 *
 * Params:
 *     builder = Builder that owns the widget object.
 *     builderLabel = Human-readable label used in log output and error
 *         messages.
 *     objectName = GtkBuilder object name to look up.
 * Returns: The requested object cast to the target type, or null when the
 *     object does not exist.
 * Throws: None.
 */
T builderObjectOrNull(T)(Builder builder, string builderLabel, string objectName)
{
    logLineVerbose("[ui] builder lookup start ", builderLabel, ".", objectName);
    auto object = builder.getObject(objectName);
    if (object is null)
    {
        logLine("[ui] missing GtkBuilder object ", builderLabel, ".", objectName,
            " (objects=", builder.getObjects().length, ")");
        return null;
    }

    logLineVerbose("[ui] builder lookup ok ", builderLabel, ".", objectName);
    return cast(T) object;
}
/** Adapter helpers between the GUI row model and the DosierSkanilo library.
 *
 * The GUI should not maintain its own JSON tree parser for scanner data.
 * Instead, it consumes the canonical `NamedBinaryBlob` model exposed by the
 * library and flattens it into `BlobRow` instances for table rendering.
 *
 * Authors: DosierSkanilo contributors
 * Copyright: Carsten Schlote, licensed under GPL-3.0-only
 * License: GPL-3.0-only
 */
module misc.bnode_static_constructor;

import core.internal.array.equality : __equals;
import dosierskanilo.metadata.torrentinfo : BNode;

/** Force instantiation of druntime equality for `torrentinfo.BNode[]`.
 *
 * This exists only to make `__equals!(BNode, BNode)` available to
 * `SumType` comparisons on some compiler/druntime versions; it has no runtime
 * effect beyond that instantiation.
 */
static this()
{
    // Force druntime equality instantiation for `torrentinfo.BNode[]`.
    // SumType!(long, string, BNode[], BDict).opEquals requires __equals!(BNode, BNode)
    // to be emitted, but this does not happen automatically with some dmd/druntime versions.
    BNode[] nodes;
    auto _ = __equals(nodes, nodes);
}

# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This software may be used and distributed according to the terms of the
# GNU General Public License version 2.

# common.py - common utilities for building commands

from __future__ import absolute_import

from sapling import (
    cmdutil,
    context,
    copies,
    error,
    extensions,
    lock as lockmod,
    mutation,
)

from sapling.ext import rebase
from sapling.i18n import _


def restackonce(
    ui,
    repo,
    rev,
    rebaseopts=None,
    childrenonly=False,
    noconflict=None,
    noconflictmsg=None,
    maxpredecessordepth=None,
):
    """Rebase all descendants of precursors of rev onto rev, thereby
    stabilzing any non-obsolete descendants of those precursors.
    Takes in an optional dict of options for the rebase command.
    If childrenonly is True, only rebases direct children of precursors
    of rev rather than all descendants of those precursors.

    NOTE(phillco): This function shouldn't be used; prefer restack.restack
    or a custom rebase using `-d _destrestack(SRC)`.
    """
    # Get visible, non-obsolete descendants of precusors of rev.

    if maxpredecessordepth is not None:
        predsquery = "predecessors(%%d, %d)" % maxpredecessordepth
    else:
        predsquery = "predecessors(%d)"

    allpredecessors = repo.revs(predsquery + " - (%d)", rev, rev)
    fmt = "%s(%%ld) - %%ld - obsolete()" % (
        "children" if childrenonly else "descendants"
    )
    descendants = repo.revs(fmt, allpredecessors, allpredecessors)

    # Nothing to do if there are no descendants.
    if not descendants:
        return

    # Overwrite source and destination, leave all other options.
    if rebaseopts is None:
        rebaseopts = {}
    rebaseopts["rev"] = descendants
    rebaseopts["dest"] = [rev]
    rebaseopts["noconflict"] = noconflict

    overrides = {
        # Explicitly disable revnum deprecation warnings. This is an internal
        # use of "rebase" that does not contain user-provided revsets.
        ("devel", "legacy.revnum"): ""
    }
    try:
        tweakdefaults = extensions.find("tweakdefaults")
    except KeyError:
        # No tweakdefaults extension -- skip this since there is no wrapper
        # to set the metadata.
        pass
    else:
        # We need to ensure that the 'operation' field in the obsmarker metadata
        # is always set to 'rebase', regardless of the current command so that
        # the restacked commits will appear as 'rebased' in smartlog.
        overrides[(tweakdefaults.globaldata, tweakdefaults.createmarkersoperation)] = (
            "rebase"
        )

    if noconflictmsg:
        overrides[("rebase", "noconflictmsg")] = noconflictmsg

    # Perform rebase.
    with repo.ui.configoverride(overrides, "restack"):
        rebase.rebase(ui, repo, **rebaseopts)


def latest(repo, rev):
    """Find the "latest version" of the given revision -- either the
    latest visible successor, or the revision itself if it has no
    visible successors.
    """
    latest = repo.revs("successors(%d)", rev).last()
    return latest if latest is not None else rev


def bookmarksupdater(repo, oldids):
    """Return a callable update(newid) updating the current bookmark
    and bookmarks bound to oldid to newid.
    """
    if type(oldids) is bytes:
        oldids = [oldids]

    def updatebookmarks(newid):
        tr = repo.currenttransaction()
        dirty = False
        for oldid in oldids:
            changes = []
            oldbookmarks = repo.nodebookmarks(oldid)
            if oldbookmarks:
                for b in oldbookmarks:
                    changes.append((b, newid))
                dirty = True
            if dirty:
                repo._bookmarks.applychanges(repo, tr, changes)

    return updatebookmarks


def rewrite(repo, old, updates, head, newbases, commitopts, mutop=None):
    """Return (nodeid, created) where nodeid is the identifier of the
    changeset generated by the rewrite process, and created is True if
    nodeid was actually created. If created is False, nodeid
    references a changeset existing before the rewrite call.
    """
    wlock = lock = tr = None
    try:
        wlock = repo.wlock()
        lock = repo.lock()
        tr = repo.transaction("rewrite")
        if len(old.parents()) > 1:  # XXX remove this unnecessary limitation.
            raise error.Abort(_("cannot amend merge changesets"))
        base = old.p1()
        updatebookmarks = bookmarksupdater(
            repo, [old.node()] + [u.node() for u in updates]
        )

        # commit a new version of the old changeset, including the update
        # collect all files which might be affected
        files = set(old.files())
        for u in updates:
            files.update(u.files())

        # Recompute copies (avoid recording a -> b -> a)
        copied = copies.pathcopies(base, head)

        # prune files which were reverted by the updates
        def samefile(f):
            if f in head.manifest():
                a = head.filectx(f)
                if f in base.manifest():
                    b = base.filectx(f)
                    return a.data() == b.data() and a.flags() == b.flags()
                else:
                    return False
            else:
                return f not in base.manifest()

        files = [f for f in files if not samefile(f)]
        # commit version of these files as defined by head
        headmf = head.manifest()

        def filectxfn(repo, ctx, path):
            if path in headmf:
                fctx = head[path]
                flags = fctx.flags()
                mctx = context.memfilectx(
                    repo,
                    ctx,
                    fctx.path(),
                    fctx.data(),
                    islink="l" in flags,
                    isexec="x" in flags,
                    copied=copied.get(path),
                )
                return mctx
            return None

        message = cmdutil.logmessage(repo, commitopts)
        if not message:
            message = old.description()

        user = commitopts.get("user") or old.user()
        # TODO: In case not date is given, we should take the old commit date
        # if we are working one one changeset or mimic the fold behavior about
        # date
        date = commitopts.get("date") or None
        extra = dict(commitopts.get("extra", old.extra()))
        extra["branch"] = head.branch()
        mutinfo = mutation.record(repo, extra, [c.node() for c in updates], mutop)
        loginfo = {
            "predecessors": " ".join(c.hex() for c in updates),
            "mutation": mutop,
        }

        new = context.memctx(
            repo,
            parents=newbases,
            text=message,
            files=files,
            filectxfn=filectxfn,
            user=user,
            date=date,
            extra=extra,
            loginfo=loginfo,
            mutinfo=mutinfo,
        )

        if commitopts.get("edit"):
            new._text = cmdutil.commitforceeditor(repo, new)
        revcount = len(repo)
        newid = repo.commitctx(new)
        new = repo[newid]
        created = len(repo) != revcount
        updatebookmarks(newid)

        tr.close()
        return newid, created
    finally:
        lockmod.release(tr, lock, wlock)


def metarewrite(repo, old, newbases, commitopts):
    """Return (nodeid, created) where nodeid is the identifier of the
    changeset generated by the rewrite process, and created is True if
    nodeid was actually created. If created is False, nodeid
    references a changeset existing before the rewrite call.
    """
    wlock = lock = tr = None
    try:
        wlock = repo.wlock()
        lock = repo.lock()
        tr = repo.transaction("rewrite")
        updatebookmarks = bookmarksupdater(repo, old.node())

        message = cmdutil.logmessage(repo, commitopts)
        if not message:
            message = old.description()

        user = commitopts.get("user") or old.user()
        date = commitopts.get("date") or None  # old.date()
        extra = dict(commitopts.get("extra", old.extra()))
        extra["branch"] = old.branch()
        preds = [old.node()]
        mutop = "metaedit"
        mutinfo = mutation.record(repo, extra, preds, mutop)
        loginfo = {"predecessors": old.hex(), "mutation": mutop}

        new = context.metadataonlyctx(
            repo,
            old,
            parents=newbases,
            text=message,
            user=user,
            date=date,
            extra=extra,
            loginfo=loginfo,
            mutinfo=mutinfo,
        )

        if commitopts.get("edit"):
            new._text = cmdutil.commitforceeditor(repo, new)
        revcount = len(repo)
        newid = repo.commitctx(new)
        new = repo[newid]
        created = len(repo) != revcount
        updatebookmarks(newid)

        tr.close()
        return newid, created
    finally:
        lockmod.release(tr, lock, wlock)


def newunstable(repo, revs):
    return repo.revs("(%ld::) - %ld", revs, revs)

# gitrevset.py
#
# Copyright 2014 Facebook, Inc.
"""map a git hash to a Mercurial hash:

    $ hg log -r "gitnode($HASH)"
    $ hg id -r "gitnode($HASH)"

short version:

    $ hg log -r "g$HASH"
    $ hg id -r "g$HASH"

"""

from __future__ import absolute_import

import re

from mercurial import error, extensions, hg, registrar, revset
from mercurial.i18n import _


revsetpredicate = registrar.revsetpredicate()

githashre = re.compile("g([0-9a-fA-F]{40,40})")

templatekeyword = registrar.templatekeyword()


@templatekeyword("gitnode")
def showgitnode(repo, ctx, templ, **args):
    """Return the git revision corresponding to a given hg rev"""
    binnode = _lookup_node(repo, ctx.hex(), from_scm_type="hg")
    # templates are expected to return an empty string when no
    # data exists
    return binnode.encode("hex") if binnode else ""


@revsetpredicate("gitnode(id)")
def gitnode(repo, subset, x):
    """``gitnode(id)``
    Return the hg revision corresponding to a given git rev."""
    l = revset.getargs(x, 1, 1, _("id requires one argument"))
    n = revset.getstring(l[0], _("id requires a string"))

    hexhgnode = _lookup_node(repo, n, from_scm_type="git")
    if not hexhgnode:
        raise error.RepoLookupError(_("unknown revision '%s'") % n)

    rev = repo[hexhgnode].rev()
    return subset.filter(lambda r: r == rev)


def _lookup_node(repo, hexnode, from_scm_type):
    gitlookupnode = "_gitlookup_%s_%s" % (from_scm_type, hexnode)

    # ui.expandpath('default') returns 'default' if there is no default
    # path. This can be the case when command is ran on the server.
    # In that case let's run lookup() command locally.
    try:
        result = repo.lookup(gitlookupnode)
    except error.RepoLookupError:
        # Note: RepoLookupError is caught here because repo.lookup()
        # can throw only this exception.
        peerpath = repo.ui.expandpath("default")

        # sshing can cause junk 'remote: ...' output to stdout, so we need to
        # redirect it temporarily so automation can parse the result easily.
        oldfout = repo.ui.fout
        try:
            repo.baseui.fout = repo.ui.ferr
            remoterepo = hg.peer(repo, {}, peerpath)
            result = remoterepo.lookup(gitlookupnode)
        except error.RepoError:
            # Note: RepoError can be thrown by hg.peer(), RepoLookupError
            # can be thrown by remoterepo.lookup(). RepoLookupError is a
            # subclass of RepoError so catching just error.RepoError is enough.
            return None
        finally:
            repo.baseui.fout = oldfout

    # Sanity check - result must be 20 chars
    if len(result) != 20:
        return None
    else:
        return result


def overridestringset(orig, repo, subset, x, *args, **kwargs):
    m = githashre.match(x)
    if m is not None:
        return gitnode(repo, subset, ("string", m.group(1)))
    return orig(repo, subset, x, *args, **kwargs)


def extsetup(ui):
    extensions.wrapfunction(revset, "stringset", overridestringset)
    revset.methods["string"] = revset.stringset
    revset.methods["symbol"] = revset.stringset

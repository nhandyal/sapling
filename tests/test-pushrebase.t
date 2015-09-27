  $ cat >> $HGRCPATH <<EOF
  > [ui]
  > ssh = python "$TESTDIR/dummyssh"
  > username = nobody <no.reply@fb.com>
  > [extensions]
  > strip =
  > EOF
  $ alias commit='hg commit -d "0 0" -A -m'
  $ alias log='hg log -G -T "{desc} [{phase}:{node|short}] {bookmarks}"'

Set up server repository

  $ hg init server
  $ cd server
  $ echo foo > a
  $ echo foo > b
  $ commit 'initial'
  adding a
  adding b

Set up client repository

  $ cd ..
  $ hg clone ssh://user@dummy/server client -q
  $ cd client
  $ echo "[extensions]" >> .hg/hgrc
  $ echo "pushrebase = $TESTDIR/../pushrebase.py" >> .hg/hgrc

Without server extension

  $ cd ../server
  $ echo 'bar' > a
  $ commit 'a => bar'

  $ cd ../client
  $ hg rm b
  $ commit 'b => xxx'
  $ echo 'baz' > b
  $ hg add b
  $ commit 'b => baz'
  $ hg push
  pushing to ssh://user@dummy/server
  searching for changes
  remote has heads on branch 'default' that are not known locally: add0c792bfce
  abort: push creates new remote head 0e3997dc0733!
  (pull and merge or see "hg help push" for details about pushing new heads)
  [255]

  $ hg --config experimental.bundle2-exp=False push --to default
  pushing to ssh://user@dummy/server
  searching for changes
  abort: bundle2 needs to be enabled on client
  [255]

  $ echo "[experimental]" >> .hg/hgrc
  $ echo "bundle2-exp = True" >> .hg/hgrc
  $ hg push --to default
  pushing to ssh://user@dummy/server
  searching for changes
  abort: no server support for 'b2x:rebase'
  [255]

  $ echo "[experimental]" >> ../server/.hg/hgrc
  $ echo "bundle2-exp = True" >> ../server/.hg/hgrc
  $ hg push --to default
  pushing to ssh://user@dummy/server
  searching for changes
  abort: no server support for 'b2x:rebase'
  [255]

Stack of non-conflicting commits should be accepted

  $ cd ../server
  $ echo "[extensions]" >> .hg/hgrc
  $ echo "pushrebase = $TESTDIR/../pushrebase.py" >> .hg/hgrc
  $ log
  @  a => bar [draft:add0c792bfce]
  |
  o  initial [draft:2bb9d20e471c]
  

  $ cd ../client
  $ log
  @  b => baz [draft:0e3997dc0733]
  |
  o  b => xxx [draft:46a2df24e272]
  |
  o  initial [public:2bb9d20e471c]
  
  $ hg push --to default
  pushing to ssh://user@dummy/server
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 3 changesets with 1 changes to 2 files (+1 heads)

  $ cd ../server
  $ hg update default
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ log
  @  b => baz [public:4cfedb0dc25f]
  |
  o  b => xxx [public:6a6d9484552c]
  |
  o  a => bar [public:add0c792bfce]
  |
  o  initial [public:2bb9d20e471c]
  

  $ cd ../client
  $ hg strip 1
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  saved backup bundle to $TESTTMP/client/.hg/strip-backup/46a2df24e272-1b034f5b-backup.hg (glob)
  $ hg pull
  pulling from ssh://user@dummy/server
  searching for changes
  no changes found
  $ hg update default
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved

Regular commits should go through without changing hash

  $ cd ../client
  $ echo '[experimental]' >> .hg/hgrc
  $ echo 'bundle2.pushback = True' >> .hg/hgrc

  $ echo 'quux' > b
  $ commit 'b => quux'
  $ log -r tip
  @  b => quux [draft:741fd2094512]
  |

  $ hg push --to default
  pushing to ssh://user@dummy/server
  searching for changes

  $ cd ../server
  $ hg update default
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved

  $ log
  @  b => quux [public:741fd2094512]
  |
  o  b => baz [public:4cfedb0dc25f]
  |
  o  b => xxx [public:6a6d9484552c]
  |
  o  a => bar [public:add0c792bfce]
  |
  o  initial [public:2bb9d20e471c]
  

Stack with conflict in tail should abort

  $ cd ../server
  $ echo 'baz' > a
  $ commit 'a => baz'

  $ cd ../client
  $ echo 'quux' > a
  $ commit 'a => quux'
  $ echo 'foofoo' > b
  $ commit 'b => foofoo'
  $ hg push --to default
  pushing to ssh://user@dummy/server
  searching for changes
  abort: conflicting changes in ['a']
  [255]

  $ hg strip 5
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  saved backup bundle to $TESTTMP/client/.hg/strip-backup/11a6a93eb344-7140e689-backup.hg (glob)
  $ cd ../server
  $ log
  @  a => baz [draft:fb983dc509b6]
  |
  o  b => quux [public:741fd2094512]
  |
  o  b => baz [public:4cfedb0dc25f]
  |
  o  b => xxx [public:6a6d9484552c]
  |
  o  a => bar [public:add0c792bfce]
  |
  o  initial [public:2bb9d20e471c]
  

Stack with conflict in head should abort

  $ cd ../client
  $ echo 'foofoo' > b
  $ commit 'b => foofoo'
  $ echo 'quux' > a
  $ commit 'a => quux'
  $ hg push --to default
  pushing to ssh://user@dummy/server
  searching for changes
  abort: conflicting changes in ['a']
  [255]

  $ hg strip 5
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  saved backup bundle to $TESTTMP/client/.hg/strip-backup/98788efd81b0-93572e45-backup.hg (glob)

  $ cd ../server
  $ log
  @  a => baz [draft:fb983dc509b6]
  |
  o  b => quux [public:741fd2094512]
  |
  o  b => baz [public:4cfedb0dc25f]
  |
  o  b => xxx [public:6a6d9484552c]
  |
  o  a => bar [public:add0c792bfce]
  |
  o  initial [public:2bb9d20e471c]
  
Pushing a merge should rebase only the latest side of the merge

  $ hg book master -r tip
  $ cd ../client
  $ hg pull -q > /dev/null
  $ hg strip -q -r tip
  $ hg up 741fd2094512
  0 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ echo "tux" > other
  $ hg add other
  $ hg commit -qm "branch left"
  $ hg book master -r tip
  moving bookmark 'master' forward from 741fd2094512
  $ hg up -q 2
  $ echo branched > c
  $ hg commit -Aqm "branch start"
  $ echo branched2 > c
  $ hg commit -qm "branch middle"
  $ hg merge -q master
  $ hg commit -qm "merge"
  $ echo ontopofmerge > c
  $ hg commit -qm "on top of merge"
  $ hg book master -r tip
  moving bookmark 'master' forward from e6b7549904cd
  $ log
  @  on top of merge [draft:9007d6a204f8] master
  |
  o    merge [draft:2c0c699d7086]
  |\
  | o  branch middle [draft:5a0cbf3df4ef]
  | |
  | o  branch start [draft:add5ec74853d]
  | |
  o |  branch left [draft:e6b7549904cd]
  | |
  o |  b => quux [public:741fd2094512]
  | |
  o |  b => baz [public:4cfedb0dc25f]
  |/
  o  b => xxx [public:6a6d9484552c]
  |
  o  a => bar [public:add0c792bfce]
  |
  o  initial [public:2bb9d20e471c]
  
  $ hg push --to master -B master
  pushing to ssh://user@dummy/server
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 4 changesets with 1 changes to 3 files (+1 heads)
  updating bookmark master
  $ cd ../server
  $ log
  o  on top of merge [public:7548c79a5591] master
  |
  o    merge [public:93a3cc822f6a]
  |\
  | o  branch middle [public:5a0cbf3df4ef]
  | |
  | o  branch start [public:add5ec74853d]
  | |
  o |  branch left [public:cf07bdf4226e]
  | |
  @ |  a => baz [public:fb983dc509b6]
  | |
  o |  b => quux [public:741fd2094512]
  | |
  o |  b => baz [public:4cfedb0dc25f]
  |/
  o  b => xxx [public:6a6d9484552c]
  |
  o  a => bar [public:add0c792bfce]
  |
  o  initial [public:2bb9d20e471c]
  
- Verify the content of the merge files is correct
  $ hg cat -r master^ c
  branched2
  $ hg cat -r master^ other
  tux

  $ hg strip -r add5ec74853d -q
  $ cd ../client
  $ hg strip -r add5ec74853d -q
  $ hg book -d master
  $ hg -R ../server book -d master

With evolution enabled, should set obsolescence markers

  $ cat >> $HGRCPATH << EOF
  > [extensions]
  > rebase =
  > 
  > [experimental]
  > evolution = all
  > EOF

  $ cd ../client
  $ hg strip -qr fb983dc509b6
  $ hg strip -qr e6b7549904cd2a7991ef25bc2e0fd910801af2cd
  $ hg up -q 741fd2094512
  $ hg mv b k
  $ commit 'b => k'
  $ hg mv k b
  $ echo 'foobar' > b
  $ commit 'b => foobar'
  $ log
  @  b => foobar [draft:e73acfaeee82]
  |
  o  b => k [draft:9467a8ee5d0d]
  |
  o  b => quux [public:741fd2094512]
  |
  o  b => baz [public:4cfedb0dc25f]
  |
  o  b => xxx [public:6a6d9484552c]
  |
  o  a => bar [public:add0c792bfce]
  |
  o  initial [public:2bb9d20e471c]
  
  $ hg push --to default
  pushing to ssh://user@dummy/server
  searching for changes
  adding changesets
  adding manifests
  adding file changes
  added 4 changesets with 2 changes to 4 files (+1 heads)
  2 new obsolescence markers

  $ hg pull
  pulling from ssh://user@dummy/server
  searching for changes
  no changes found
  $ hg debugobsolete | sort
  9467a8ee5d0d993ba68d94946c9d4a3cae8d31ff 0d76868c25e6789734c06e056f235e1fa223da74 * (glob)
  e73acfaeee82005b2379f82efb73123cbb74a733 d53a62ed14be0980584e1f92f9c47031ef806a62 * (glob)
  $ hg up d53a62ed14be
  2 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ log
  @  b => foobar [public:d53a62ed14be]
  |
  o  b => k [public:0d76868c25e6]
  |
  o  branch left [public:cf07bdf4226e]
  |
  o  a => baz [public:fb983dc509b6]
  |
  o  b => quux [public:741fd2094512]
  |
  o  b => baz [public:4cfedb0dc25f]
  |
  o  b => xxx [public:6a6d9484552c]
  |
  o  a => bar [public:add0c792bfce]
  |
  o  initial [public:2bb9d20e471c]
  

  $ cd ../server
  $ hg log -r 0d76868c25e6 -T '{file_copies}\n'
  k (b)
  $ log
  o  b => foobar [public:d53a62ed14be]
  |
  o  b => k [public:0d76868c25e6]
  |
  o  branch left [public:cf07bdf4226e]
  |
  @  a => baz [public:fb983dc509b6]
  |
  o  b => quux [public:741fd2094512]
  |
  o  b => baz [public:4cfedb0dc25f]
  |
  o  b => xxx [public:6a6d9484552c]
  |
  o  a => bar [public:add0c792bfce]
  |
  o  initial [public:2bb9d20e471c]
  
Test pushing master bookmark, fast forward

  $ hg book -r fb983dc509b6 master
  $ cd ../client
  $ hg book master
  $ echo 'babar' > b
  $ commit 'b => babar'
  $ hg log -r master -T"{node}\n"
  56b2e094996609874ae1c9aae1626bfba61d07d8
  $ hg push --to master
  pushing to ssh://user@dummy/server
  searching for changes
  updating bookmark master
  $ hg log -r master -R ../server -T"{node}\n"
  56b2e094996609874ae1c9aae1626bfba61d07d8

Test pushing bookmark with no new commit

  $ hg book stable -r fb983dc509b6
  $ hg book stable -r fb983dc509b6^ -R ../server
  $ hg push -r stable --to stable
  pushing to ssh://user@dummy/server
  searching for changes
  no changes found
  updating bookmark stable
  [1]
  $ hg log -r stable -R ../server
  changeset:   5:fb983dc509b6
  bookmark:    stable
  user:        test
  date:        Thu Jan 01 00:00:00 1970 +0000
  summary:     a => baz
  

  $ cd ..

Test that hooks are fired with the correct variables

  $ hg init hookserver
  $ cd hookserver
  $ cat >> .hg/hgrc <<EOF
  > [hooks]
  > changegroup = python "$TESTDIR/printenv.py" changegroup
  > incoming = python "$TESTDIR/printenv.py" incoming
  > outgoing = python "$TESTDIR/printenv.py" outgoing
  > prechangegroup = python "$TESTDIR/printenv.py" prechangegroup
  > preoutgoing = python "$TESTDIR/printenv.py" preoutgoing
  > pretxnchangegroup = python "$TESTDIR/printenv.py" pretxnchangegroup
  > txnclose = python "$TESTDIR/printenv.py" txnclose
  > pretxnclose = python "$TESTDIR/printenv.py" pretxnclose
  > [extensions]
  > pushrebase = $TESTDIR/../pushrebase.py
  > EOF
  $ touch file && hg ci -Aqm initial
  pretxnclose hook:
  txnclose hook:
  $ hg bookmark master
  pretxnclose hook:
  txnclose hook:
  $ cd ../

  $ hg clone hookserver hookclient
  preoutgoing hook:
      HG_SOURCE    = clone
  outgoing hook:
      HG_NODE      = 0000000000000000000000000000000000000000
      HG_SOURCE    = clone
  updating to branch default
  1 files updated, 0 files merged, 0 files removed, 0 files unresolved
  $ cd hookclient
  $ cat >> .hg/hgrc <<EOF
  > [extensions]
  > pushrebase = $TESTDIR/../pushrebase.py
  > EOF
  $ echo >> file && hg ci -Aqm first
  $ hg push --to master
  pushing to $TESTTMP/hookserver
  searching for changes
  prechangegroup hook:
      HG_BUNDLE2   = 1
      HG_SOURCE    = push
  pretxnchangegroup hook:
      HG_BUNDLE2   = 1
      HG_NODE      = 4fcee35c508c1019667f72cae9b843efa8908701
      HG_SOURCE    = push
  pretxnclose hook:
      HG_BUNDLE2   = 1
      HG_NODE      = 4fcee35c508c1019667f72cae9b843efa8908701
      HG_SOURCE    = push
  txnclose hook:
      HG_BUNDLE2   = 1
      HG_NODE      = 4fcee35c508c1019667f72cae9b843efa8908701
      HG_SOURCE    = push
  changegroup hook:
      HG_BUNDLE2   = 1
      HG_NODE      = 4fcee35c508c1019667f72cae9b843efa8908701
      HG_SOURCE    = push
  incoming hook:
      HG_BUNDLE2   = 1
      HG_NODE      = 4fcee35c508c1019667f72cae9b843efa8908701
      HG_SOURCE    = push
  $ cd ../

Copied from mercuriat test-bundle2-format.t
  $ cat > bundle2.py << EOF
  > """A small extension to test bundle2 implementation"""
  > 
  > import sys, os
  > from mercurial import cmdutil
  > from mercurial import util
  > from mercurial import bundle2
  > from mercurial import error
  > 
  > cmdtable = {}
  > command = cmdutil.command(cmdtable)
  > 
  > @command('bundle2', [], '[OUTPUTFILE]')
  > def cmdbundle2(ui, repo, path=None, **opts):
  >     """write a bundle2 container on standard output"""
  >     bundler = bundle2.bundle20(ui)
  > 
  >     part = bundler.newpart('check:heads')
  >     part.data = '01234567890123456789'
  > 
  >     if path is None:
  >        file = sys.stdout
  >     else:
  >         file = open(path, 'wb')
  > 
  >     try:
  >         for chunk in bundler.getchunks():
  >             file.write(chunk)
  >     except RuntimeError, exc:
  >         raise util.Abort(exc)
  > @command('unbundle2', [], '')
  > def cmdunbundle2(ui, repo, replypath=None):
  >     """process a bundle2 stream from stdin on the current repo"""
  >     try:
  >         tr = None
  >         lock = repo.lock()
  >         tr = repo.transaction('processbundle')
  >         try:
  >             unbundler = bundle2.getunbundler(ui, sys.stdin)
  >             op = bundle2.processbundle(repo, unbundler, lambda: tr)
  >             tr.close()
  >         except error.BundleValueError, exc:
  >             raise util.Abort('missing support for %s' % exc)
  >         except error.PushRaced, exc:
  >             raise util.Abort('push race: %s' % exc)
  >     finally:
  >         if tr is not None:
  >             tr.release()
  >         lock.release()
  >         remains = sys.stdin.read()
  >         ui.write('%i unread bytes\n' % len(remains))
  >     if op.records['song']:
  >         totalverses = sum(r['verses'] for r in op.records['song'])
  >         ui.write('%i total verses sung\n' % totalverses)
  >     for rec in op.records['changegroup']:
  >         ui.write('addchangegroup return: %i\n' % rec['return'])
  >     if op.reply is not None and replypath is not None:
  >         file = open(replypath, 'wb')
  >         for chunk in op.reply.getchunks():
  >             file.write(chunk)
  > EOF
  $ cat >> $HGRCPATH << EOF
  > [extensions]
  > bundle2=$TESTTMP/bundle2.py
  > [experimental]
  > EOF

Now create and unbundle a bundle with a conflicting check:heads part
  $ hg init -q headcheck
  $ cd headcheck
  $ cat >> .hg/hgrc <<EOF
  > [extensions]
  > pushrebase = $TESTDIR/../pushrebase.py
  > EOF
  $ hg bundle2 checkhead.hg2
  $ hg unbundle2 < checkhead.hg2
  0 unread bytes

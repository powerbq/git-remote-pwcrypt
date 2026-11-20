==================
git-remote-pwcrypt
==================

-----------------------------------------------------------
Passphrase-encrypted git remote (fork of git-remote-gcrypt)
-----------------------------------------------------------

:Manual section: 1

Description
===========

git-remote-pwcrypt is a fork of git-remote-gcrypt
(https://github.com/spwhitton/git-remote-gcrypt, upstream commit a5ff704).
It encrypts the whole repository with a passphrase only: there are no
GPG keys (see "Passphrase mode"). For GPG keys use git-remote-gcrypt.
It uses its own URL scheme (``pwcrypt::``), configuration keys
(``pwcrypt-*``, ``pwcrypt.*``), environment variables (``PWCRYPT_*``)
and local directory, so it can be installed next to git-remote-gcrypt.
The two are not interchangeable: git-remote-gcrypt cannot read a
pwcrypt remote and pwcrypt cannot read a gcrypt remote.


git-remote-pwcrypt is a git remote helper to push and pull from
repositories encrypted with a passphrase through GnuPG's symmetric
encryption, using a custom format.  This remote
helper handles URIs prefixed with `pwcrypt::`.

Supported backends are `local`, `rsync://` and `sftp://`, where the
repository is stored as a set of files, or instead any `<giturl>`
where pwcrypt will store the same representation in a git repository,
bridged over arbitrary git transport.  Prefer `local` or `rsync://` if
you can use one of those; see "Performance" below for discussion.

There is also an experimental `rclone://` backend for early adoptors
only (you have been warned).

The aim is to provide confidential, authenticated git storage and
collaboration using typical untrusted file hosts or services.

Installation
............


* run the supplied ``install.sh`` script (or copy ``git-remote-pwcrypt``
  into a directory in your ``PATH``)

Quickstart
..........

Create an encrypted remote by pushing to it::

    git remote add cryptremote pwcrypt::rsync://example.com/repo
    git push cryptremote master
    > pwcrypt: Setting up new repository
    > pwcrypt: NEW passphrase for cryptremote:
    > pwcrypt: repeat NEW passphrase:
    > pwcrypt: Remote ID is :id:7VigUnLVYVtZx8oir34R
    > [ more lines .. ]
    > To pwcrypt::[...]
    > * [new branch]      master -> master

Configuration
=============

The following ``git-config(1)`` variables are supported:

``pwcrypt.gpg-args``
    The contents of this setting are passed as arguments to gpg.
    E.g. ``--use-agent``.

``remote.<name>.pwcrypt-rsync-put-flags``
    ..
``pwcrypt.rsync-put-flags``
    Flags to be passed to ``rsync`` when uploading to a remote using the
    ``rsync://`` backend. If the flags are set to a specific remote, the
    global flags, if also set, will not be applied for that remote.

``remote.<name>.pwcrypt-require-explicit-force-push``
    ..
``pwcrypt.require-explicit-force-push``
    A longstanding bug is that every git push effectively has a ``--force``.

    If this flag is set to ``true``, git-remote-pwcrypt will refuse to push,
    unless ``--force`` is passed, or refspecs are prefixed with ``+``.

    There is a potential solution here: https://bugs.debian.org/877464#32

Environment variables
=====================

*PWCRYPT_FULL_REPACK*
    When set (to anything other than the empty string), this environment
    variable forces a full repack when pushing.

*PWCRYPT_ASKPASS*
    Program that prints the passphrase on stdout;
    it gets the prompt as its only argument. Without it the passphrase
    is read from ``/dev/tty``.

Passphrase mode
===============

The manifest is encrypted with ``gpg --symmetric`` (AES-256, iterated
and salted S2K with SHA-512); no GPG keys or signatures are used.
Packfiles are encrypted with random keys listed in the manifest, as in
git-remote-gcrypt.

* The passphrase is asked once per git command (``fetch``, ``push``,
  ``clone``, ``pull``) and kept only in the memory of that helper
  process. It is never written to disk, exported to the environment,
  or passed on a command line: it reaches gpg through a pipe from the
  ``printf`` shell builtin, with ``--no-symkey-cache`` so gpg-agent
  does not keep it.
* A first push to a new remote asks for a new passphrase twice.
  A wrong passphrase is retried up to three times.
* The decrypted manifest is accepted only if gpg reports a
  passphrase-encrypted, integrity-protected message; an unencrypted
  OpenPGP packet planted on the server is rejected.
* Integrity comes from the passphrase alone: anyone who knows it can
  write a valid manifest.

``remote.<name>.pwcrypt-s2k-count``
    ..
``pwcrypt.s2k-count``
    S2K iteration count used when the manifest is written (default and
    maximum: 65011712). Decryption reads the count from the manifest.

``git-remote-pwcrypt --calibrate [MS]``
    Measures this machine and suggests ``pwcrypt.s2k-count`` for a target
    decryption time (default 100 ms). GnuPG caps the count, so long
    targets such as 1 s may not be reachable; the command says so.

``git-remote-pwcrypt --change-passphrase REMOTE``
    Run inside the repository. Asks for the current passphrase, then the
    new one twice, re-encrypts only the manifest, checks that it decrypts
    with the new passphrase, and uploads it. Packfiles are not rewritten,
    so whoever kept an old manifest and knows the old passphrase can
    still read the packs it lists; run ``--reencrypt`` afterwards.

``git-remote-pwcrypt --reencrypt REMOTE``
    Run inside the repository. Downloads every packfile, writes the whole
    history again as one pack under a fresh random key, deletes the old
    packs and writes a new manifest, keeping the passphrase.
    Unlike ``PWCRYPT_FULL_REPACK=1 git push``, it works when there is
    nothing new to push. With a git backend such as GitHub, the old
    objects become unreachable but the host may keep them for a while.

Set up::

    git remote add origin pwcrypt::git@github.com:user/env.git
    git push origin HEAD

Clone::

    git clone pwcrypt::git@github.com:user/env.git

Examples
========

How to use a git backend::

    # notice that the target git repo must already exist and its
    # `next` branch will be overwritten!
    git remote add gitcrypt pwcrypt::git@example.com:repo#next
    git push gitcrypt master

The URL fragment (``#next`` here) indicates which backend branch is used.

Notes
=====

Collaboration
    Everyone who knows the passphrase can read and push. There is no
    per-person access: to remove someone, change the passphrase and run
    ``--reencrypt``.

Dependencies
    ``rsync``, ``curl`` and ``rclone`` for remotes ``rsync:``, ``sftp:`` and
    ``rclone:`` respectively. The main executable requires a POSIX-compliant
    shell that supports ``local``.

GNU Privacy Guard
    GnuPG 2.2.7 or later is needed (for ``--no-symkey-cache`` and
    ``--pinentry-mode loopback``); tested with 2.4.4. No GPG keys are
    needed.

Remote ID
    The Remote ID is not secret; it only ensures that two repositories
    can be distinguished.  You will see
    a warning if the Remote ID changes, which should only happen if the
    remote was re-created.

Performance
    Using an arbitrary `<giturl>` or an `sftp://` URI requires
    uploading the entire repository history with each push.  This
    means that pushes of your repository become slower over time, as
    your git history becomes longer, and it can easily get to the
    point that continued usage of git-remote-pwcrypt is impractical.

    Thus, you should use these backends only when you know that your
    repository will not ever grow very large, not just that it's not
    large now.  This means that these backends are inappropriate for
    most repositories, and likely suitable only for unusual cases,
    such as small credential stores.  Even then, use `rsync://` if you
    can.  Note, however, that `rsync://` won't work with a repository
    hosting service like Gitolite, GitHub or GitLab.

rsync URIs
    The URI format for the rsync backend is ``rsync://user@host/path``,
    which translates to the rsync location ``user@host:/path``,
    accessed over ssh. Note that the path is absolute, not relative to the
    home directory. An earlier non-standard URI format is also supported:
    ``rsync://user@host:path``, which translates to the rsync location
    ``user@host:path``

rclone backend
    In addition to adding the rclone backend as a remote with URI like
    ``pwcrypt::rclone://remote:subdir``, you must add the remote to the
    rclone configuration too.  This is typically done by executing
    ``rclone config``.  See rclone(1).

    The rclone backend is considered experimental and is for early
    adoptors only.  You have been warned.

Repository format
.................

| `PwEnc(X):`     Encrypt with the passphrase (gpg --symmetric, with MDC)
| `Encrypt(K,X):` Encrypt using symmetric-key algorithm
| `Hash(X):`      SHA-2/256
|
| `B:` branch list
| `L:` list of the hash (`Hi`) and key (`Ki`) for each packfile
| `R:` Remote ID
|
| To write the repository:
|
| Store each packfile `P` as `Encrypt(Ki, P)` → `P'` in filename `Hi`
|   where `Ki` is a new random string and `Hash(P')` → `Hi`
| Store `PwEnc(B || L || R)` in the manifest
|
| To read the repository:
|
| Get manifest, decrypt with the passphrase and check integrity → `(B, L, R)`
| Warn if `R` does not match previously seen Remote ID
| for each `Hi, Ki` in `L`:
|   Get file `Hi` from the server → `P'`
|   Verify `Hash(P')` matches `Hi`
|   Decrypt `P'` using `Ki` → `P` then open `P` with git

Manifest file
.............

Example manifest file (with ellipsis for brevity)::

    $ gpg -d 91bd0c092128cf2e60e1a608c31e92caf1f9c1595f83f2890ef17c0e4881aa0a
    542051c7cd152644e4995bda63cc3ddffd635958 refs/heads/next
    3c9e76484c7596eff70b21cbe58408b2774bedad refs/heads/master
    pack :SHA256:f2ad50316...cd4ba67092dc4 z8YoAnFpMlW...3PkI2mND49P1qm
    pack :SHA256:a6e17bb4c...426492f379584 82+k2cbiUn7...dgXfyX6wXGpvVa
    keep :SHA256:f2ad50316...cd4ba67092dc4 1
    repo :id:OYiSleGirtLubEVqJpFF

Each item extends until newline, and matches one of the following:

``<sha-1> <gitref>``
    Git object id and its ref

``pack :<hashtype>:<hash> <key>``
    Packfile hash (`Hi`) and corresponding symmetric key (`Ki`).

``keep :<hashtype>:<hash> <generation>``
    Packfile hash and its repack generation

``repo <id>``
    The remote id

``extn <name> ...``
    Extension field, preserved but unused.

Detecting pwcrypt repos
=======================

To detect if a git url is a pwcrypt repo, use: ``git-remote-pwcrypt --check url``
Exit status is 0 if the repo exists and can be decrypted, 1 if the repo
uses pwcrypt but could not be decrypted, and 100 if the repo is not
encrypted with pwcrypt (or could not be accessed).

Note that this has to fetch the repo contents into the local git
repository, the same as is done when using a pwcrypt repo.

Known issues
============

Every git push effectively has ``--force``.  Be sure to pull before
pushing.

git-remote-pwcrypt can decide to repack the remote without warning,
which means that your push can suddenly take significantly longer than
you were expecting, as your whole history has to be reuploaded.
This push might fail over a poor link.

git-remote-pwcrypt might report a repository as "not found" when the
repository does in fact exist, but git-remote-pwcrypt is having
authentication, port, or network connectivity issues.

See also
========

git-remote-helpers(1), gpg(1)

Credits
=======

The original author of git-remote-pwcrypt was GitHub user bluss.

The de facto maintainer in 2013 and 2014 was Joey Hess.

The current maintainer, since 2016, is Sean Whitton
<spwhitton@spwhitton.name>.

License
=======

This document and git-remote-pwcrypt are licensed under identical terms,
GPL-3 (or 2+); see the git-remote-pwcrypt file.

.. this document generates a man page with rst2man
.. vim: ft=rst tw=72 sts=4

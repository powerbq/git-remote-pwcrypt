Name:       git-remote-pwcrypt
Version:    1.0
Release:    1%{?dist}
Summary:    Passphrase-encrypted git remote (fork of git-remote-gcrypt)

Group:      Development Tools
License:    GPLv3
URL:        https://github.com/powerbq/%{name}
Source0:    https://github.com/powerbq/%{name}/archive/refs/tags/%{version}.tar.gz#/%{name}-%{version}.tar.gz

BuildArch:  noarch

BuildRequires:  python3-docutils
Requires:   gnupg2 git-core

%description
This lets git store git repositories in encrypted form, protected by a
passphrase only (no GPG keys).  It is a fork of git-remote-gcrypt.
It supports storing repositories on rsync or sftp servers.
It can also store the encrypted git repository inside a remote git
repository. All the regular git commands like git push and git pull
can be used to operate on such an encrypted repository.

The aim is to provide confidential, authenticated git storage and
collaboration using typical untrusted file hosts or services.

%prep
%setup -q -n %{name}-%{version}

%build
:

%install
export DESTDIR="%{buildroot}"
export prefix="%{_prefix}"
./install.sh

%files
%{_bindir}/%{name}
%{_mandir}/man1/%{name}.1*
%license COPYING
%doc CHANGELOG CONTRIBUTING.rst README.rst

%changelog
* Fri Nov 20 2026 powerbq <powerbq@gmail.com> - 1.0-1
- Fork of git-remote-gcrypt as git-remote-pwcrypt: passphrase-only encryption

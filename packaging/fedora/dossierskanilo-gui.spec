Name:           dosierskanilo-gui
Version:        0.12.1
Release:        1%{?dist}
Summary:        GTK desktop frontend for DosierSkanilo
License:        GPL-3.0-only
URL:            https://gitlab.vahanus.net/dlang/dosierskanilo-gui
Source0:        https://gitlab.vahanus.net/dlang/dosierskanilo-gui/-/archive/v%{version}/dosierskanilo-gui-v%{version}.tar.gz
BuildRequires:  ldc
BuildRequires:  dub
BuildRequires:  gcc
BuildRequires:  gtk3-devel
BuildRequires:  gstreamer1-devel
BuildRequires:  gstreamer1-plugins-base-devel
BuildRequires:  sqlite-devel
Requires:       gtk3
Requires:       gstreamer1
Requires:       gstreamer1-plugins-base
Requires:       sqlite-libs
Recommends:     mediainfo
Recommends:     gstreamer1-plugins-good
Recommends:     file
Recommends:     unzip
Recommends:     tar
Recommends:     unrar
Recommends:     p7zip
Suggests:       gstreamer1-plugins-bad-free
Suggests:       gstreamer1-libav
Suggests:       gstreamer1-plugins-ugly-free
Suggests:       python3

%description
GTK desktop frontend for browsing and filtering DosierSkanilo JSON indexes.

%prep
%autosetup -n dosierskanilo-gui-v%{version}

%build
DC=ldc2 dub build --build=release --compiler=ldc2

%install
install -Dpm0755 build/bin/dosierskanilo-gui %{buildroot}%{_bindir}/dosierskanilo-gui
install -Dpm0644 LICENSE.md %{buildroot}%{_licensedir}/%{name}/LICENSE.md

%files
%{_bindir}/dosierskanilo-gui
%license %{_licensedir}/%{name}/LICENSE.md

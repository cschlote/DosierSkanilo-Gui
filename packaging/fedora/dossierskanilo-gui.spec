Name:           dosierskanilo-gui
Version:        0.6.0
Release:        1%{?dist}
Summary:        GTK desktop frontend for DosierSkanilo
License:        CC-BY-NC-SA
URL:            https://gitlab.vahanus.net/dlang/dosierskanilo-gui
Source0:        https://gitlab.vahanus.net/dlang/dosierskanilo-gui/-/archive/v%{version}/dosierskanilo-gui-v%{version}.tar.gz
BuildRequires:  ldc
BuildRequires:  dub
BuildRequires:  gtk3-devel
Requires:       gtk3
Requires:       gstreamer1

%description
GTK desktop frontend for browsing and filtering DosierSkanilo JSON indexes.

%prep
%autosetup -n dosierskanilo-gui-v%{version}

%build
DC=ldc2 dub build --build=release --compiler=ldc2

%install
install -Dpm0755 build/bin/dosierskanilo-gui %{buildroot}%{_bindir}/dosierskanilo-gui

%files
%{_bindir}/dosierskanilo-gui

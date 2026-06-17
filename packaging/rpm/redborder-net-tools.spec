Name: redborder-net-tools
Version: %{__version}
Release: %{__release}%{?dist}
BuildArch: noarch

License: AGPL 3.0
URL: https://github.com/redBorder/redborder-net-tools
Source0: %{name}-%{version}.tar.gz

Requires: ruby

Summary: redBorder Proxy Net Tools polling daemon

%description
%{summary}

%prep
%setup -qn %{name}-%{version}

%build

%install
mkdir -p %{buildroot}/usr/lib/redborder/scripts
install -D -m 0755 resources/scripts/redborder_net_tools.rb %{buildroot}/usr/lib/redborder/scripts/redborder_net_tools.rb
install -D -m 0644 resources/systemd/redborder-net-tools.service %{buildroot}/usr/lib/systemd/system/redborder-net-tools.service

%post
systemctl daemon-reload

%preun
if [ "$1" = 0 ]; then
  systemctl stop redborder-net-tools.service > /dev/null 2>&1 || true
  systemctl disable redborder-net-tools.service > /dev/null 2>&1 || true
fi

%files
%defattr(0755,root,root)
/usr/lib/redborder/scripts/redborder_net_tools.rb
%defattr(0644,root,root)
/usr/lib/systemd/system/redborder-net-tools.service

%doc

%changelog
* Tue Jun 17 2026 Miguel Negrón <manegron@redborder.com> - 0.0.1
- First spec version

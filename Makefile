
include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-hp-lite
PKG_VERSION:=6.0
PKG_RELEASE:=2
PKG_PO_VERSION:=$(PKG_VERSION)-r$(PKG_RELEASE)
PKG_MAINTAINER:=zyh <1540187368@qq.com>
PKG_LICENSE:=Apache-2.0
PKG_LICENSE_FILES:=LICENSE

LUCI_TITLE:=LuCI Support for hp lite
LUCI_DEPENDS:=+luci-base +uci
LUCI_PKGARCH:=all

define Package/$(PKG_NAME)/postinst
#!/bin/sh
chmod 755 "$${IPKG_INSTROOT}/etc/init.d/hp-lite" 2>/dev/null || true
[ -n "$${IPKG_INSTROOT}" ] || {
	rm -f /tmp/luci-indexcache*
	rm -rf /tmp/luci-modulecache/
	/etc/init.d/rpcd reload 2>/dev/null || true
}
exit 0
endef

define Package/$(PKG_NAME)/prerm
#!/bin/sh
case "$$1" in
	remove|purge|deinstall|uninstall|"")
		if [ -z "$${IPKG_INSTROOT}" ] && [ -x /etc/init.d/hp-lite ]; then
			/etc/init.d/hp-lite stop >/dev/null 2>&1 || true
			/etc/init.d/hp-lite disable >/dev/null 2>&1 || true
		fi

		ROOT="$${IPKG_INSTROOT}"
		CRON="$${ROOT}/etc/crontabs/root"

		if [ -f "$${CRON}" ]; then
			sed -i '/# hp-lite-log-clean/d' "$${CRON}" 2>/dev/null || true
		fi

		rm -f "$${ROOT}/usr/bin/hp-lite"
		rm -f "$${ROOT}/tmp/hp-lite.upload"
		rm -f "$${ROOT}/etc/config/hp-lite"
		rm -f "$${ROOT}"/etc/rc.d/*hp-lite 2>/dev/null || true
		rm -rf "$${ROOT}/var/log/hp-lite"
		rm -rf "$${ROOT}/tmp/hp-lite"
		rm -f "$${ROOT}"/tmp/luci-indexcache*
		rm -rf "$${ROOT}/tmp/luci-modulecache"

		if [ -z "$${ROOT}" ] && [ -x /etc/init.d/cron ]; then
			/etc/init.d/cron reload >/dev/null 2>&1 || /etc/init.d/cron restart >/dev/null 2>&1 || true
		fi
		;;
esac
exit 0
endef

define Package/$(PKG_NAME)/postrm
#!/bin/sh
case "$$1" in
	remove|purge|deinstall|uninstall|"")
		;;
	*)
		exit 0
		;;
esac

ROOT="$${IPKG_INSTROOT}"
CRON="$${ROOT}/etc/crontabs/root"

if [ -f "$${CRON}" ]; then
	sed -i '/# hp-lite-log-clean/d' "$${CRON}" 2>/dev/null || true
fi

rm -f "$${ROOT}/usr/bin/hp-lite"
rm -f "$${ROOT}/tmp/hp-lite.upload"
rm -f "$${ROOT}/etc/config/hp-lite"
rm -f "$${ROOT}"/etc/rc.d/*hp-lite 2>/dev/null || true
rm -rf "$${ROOT}/var/log/hp-lite"
rm -rf "$${ROOT}/tmp/hp-lite"
rm -f "$${ROOT}"/tmp/luci-indexcache*
rm -rf "$${ROOT}/tmp/luci-modulecache"

if [ -z "$${ROOT}" ] && [ -x /etc/init.d/cron ]; then
	/etc/init.d/cron reload >/dev/null 2>&1 || /etc/init.d/cron restart >/dev/null 2>&1 || true
fi

exit 0
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature


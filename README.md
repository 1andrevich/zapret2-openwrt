# zapret2-openwrt

Zapret — это не VPN! Zapret — это утилита для обхода DPI.

[Страница загрузки](https://github.com/1andrevich/zapret2-openwrt/releases)

## Установка

Выполните на роутере. Скрипт сам определит архитектуру устройства и последний релиз.

**OpenWrt 24.10+ (apk):**
```sh
ARCH=$(. /etc/openwrt_release; echo "$DISTRIB_ARCH")
VER=$(wget -qO- https://api.github.com/repos/1andrevich/zapret2-openwrt/releases/latest | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p' | head -n1)
URL=https://github.com/1andrevich/zapret2-openwrt/releases/download/v$VER
wget -O /etc/apk/keys/zapret2-1andrevich.pub $URL/zapret2-1andrevich.pub   # добавить ключ подписи (один раз)
cd /tmp && wget $URL/zapret2_${VER}_${ARCH}.apk $URL/luci-app-zapret2_${VER}_all.apk
apk add ./zapret2_${VER}_${ARCH}.apk ./luci-app-zapret2_${VER}_all.apk
```

**OpenWrt 23.05 (opkg):**
```sh
ARCH=$(. /etc/openwrt_release; echo "$DISTRIB_ARCH")
VER=$(wget -qO- https://api.github.com/repos/1andrevich/zapret2-openwrt/releases/latest | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p' | head -n1)
URL=https://github.com/1andrevich/zapret2-openwrt/releases/download/v$VER
cd /tmp && wget $URL/zapret2_${VER}_${ARCH}.ipk $URL/luci-app-zapret2_${VER}_all.ipk
opkg install ./zapret2_${VER}_${ARCH}.ipk ./luci-app-zapret2_${VER}_all.ipk
```

Сервис запускается автоматически при установке и при загрузке роутера. Настройка — в **LuCI → Службы → Zapret2**.

> Не хотите добавлять ключ подписи? Тогда устанавливайте через `apk add --allow-untrusted ...`.

## Скриншоты

![image](https://github.com/user-attachments/assets/b79940b3-6a0d-4310-bd58-e461be004397)


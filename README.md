# zapret2-openwrt

Zapret — это не VPN! Zapret — это утилита для обхода DPI.

[Страница загрузки](https://github.com/1andrevich/zapret2-openwrt/releases)

## Установка

### 📶 OpenWrt 25.12+ (APK)
```sh
wget -O /etc/apk/keys/zapret2-1andrevich.pub https://github.com/1andrevich/zapret2-openwrt/releases/latest/download/zapret2-1andrevich.pub
wget -O /tmp/zapret2.apk "https://github.com/1andrevich/zapret2-openwrt/releases/latest/download/zapret2_$(. /etc/os-release; echo "$OPENWRT_ARCH").apk"
wget -O /tmp/luci-app-zapret2.apk https://github.com/1andrevich/zapret2-openwrt/releases/latest/download/luci-app-zapret2.apk
apk add /tmp/zapret2.apk /tmp/luci-app-zapret2.apk
```

### 📶 OpenWrt 23.05+ (opkg)
```sh
wget -O /tmp/zapret2.ipk "https://github.com/1andrevich/zapret2-openwrt/releases/latest/download/zapret2_$(. /etc/os-release; echo "$OPENWRT_ARCH").ipk"
wget -O /tmp/luci-app-zapret2.ipk https://github.com/1andrevich/zapret2-openwrt/releases/latest/download/luci-app-zapret2.ipk
opkg update
opkg install /tmp/zapret2.ipk /tmp/luci-app-zapret2.ipk
```

Сервис запускается автоматически при установке и при загрузке роутера. Настройка — в **LuCI → Службы → Zapret2**.

## Скриншоты

![image](https://github.com/user-attachments/assets/4ad3eac5-44a6-493c-a001-997d0c1a36eb)


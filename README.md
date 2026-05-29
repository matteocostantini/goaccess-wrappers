# GoAccess

[GH ISSUE](https://github.com/allinurl/goaccess/issues/1789)

## Artifacts
[GoAccess Downloads](https://goaccess.io/download)

```
wget -O - https://deb.goaccess.io/gnugpg.key | gpg --dearmor | sudo tee /usr/share/keyrings/goaccess.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/goaccess.gpg arch=$(dpkg --print-architecture)] https://deb.goaccess.io/ $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/goaccess.list
sudo apt-get update
sudo apt-get install goaccess
```

```
find /usr/share/ -type f -name 'GeoLite2-Country*'
find /var/lib/ -type f -name 'GeoLite2-Country*'

wget https://github.com/maxmind/geoipupdate/releases/download/v7.1.1/geoipupdate_7.1.1_linux_amd64.deb
dpkg -i geoipupdate_7.1.1_linux_amd64.deb
nano /etc/GeoIP.conf
```


```shell
/opt/scripts/update_scripts/geoip_update.sh
geoipupdate -f /etc/GeoIP.conf -d /usr/share/GeoIP/ --verbose
ls -lah /usr/share/GeoIP/
```

```shell
nano /etc/goaccess/goaccess.conf
```

## Console Use

```shell
# Start GoAccess as a console
goaccess -c access.log \
  --log-format=COMBINED \
	--geoip-database=/usr/share/GeoIP/GeoLite2-City.mmdb \
	--geoip-database=/usr/share/GeoIP/GeoLite2-ASN.mmdb \
	--exclude-ip=37.179.5.219 \
	--exclude-ip=62.196.80.2 \
	--exclude-ip=178.32.137.183
```



## RealTime-HTML Use

[RealTime-HTML-IPv4](https://oneuptime.com/blog/post/2026-03-20-goaccess-realtime-ipv4-web-traffic-analysis/view)

```shell
# WS no reversed proxed | no cloudflare proxy | ufw allow 7890 ma la porta in uscita di AP blocca la 7890, non blocca la 8090
goaccess access.log \
	--log-format=COMBINED \
	--geoip-database=/usr/share/GeoIP/GeoLite2-City.mmdb \
	--geoip-database=/usr/share/GeoIP/GeoLite2-ASN.mmdb \
	--exclude-ip=37.179.5.219 \
	--output=/var/www/analytics-aragorn3.interagisco.it/web/live-report.html \
	--real-time-html \
	--addr=0.0.0.0 \
	--port=7890 \
	--ws-url=wss://analytics-aragorn3.interagisco.it
```


```shell
# WS reversed proxed | no cloudflare proxy 
goaccess access.log \
	--log-format=COMBINED \
	--geoip-database=/usr/share/GeoIP/GeoLite2-City.mmdb \
	--geoip-database=/usr/share/GeoIP/GeoLite2-ASN.mmdb \
	--exclude-ip=37.179.5.219 \
	--output=/var/www/analytics-aragorn3.interagisco.it/web/live-report.html \
	--real-time-html \
	--ws-url=wss://analytics-aragorn3.interagisco.it:443/ws \
	--addr=127.0.0.1 \
	--port=7890
```
	--ws-auth=jwt:ciao \
	--ws-auth-expire=1h \
use zcat -f <pattern> | goaccess ...

```shell
a2enmod proxy proxy_http proxy_wstunnel rewrite
```

```
# WebSocket reverse proxy per GoAccess
RewriteEngine On

# Upgrade WebSocket
RewriteCond %{HTTP:Upgrade} =websocket [NC]
RewriteRule ^/ws/?$ ws://127.0.0.1:7890/ [P,L]

ProxyPass "/ws"  "ws://127.0.0.1:7890/"
ProxyPassReverse "/ws" "ws://127.0.0.1:7890/"

# Necessario per evitare problemi con proxy
ProxyPreserveHost On
```


```shell
# WS  reversed proxed | no cloudflare proxy 
zcat -f *access* | goaccess --log-format=COMBINED \ 
	-o /var/www/analytics-aragorn3.interagisco.it/web/live-report.html \
	--real-time-html \
	--addr=0.0.0.0 \
	--ws-url=wss://analytics-aragorn3.interagisco.it/goaccess-ws
```
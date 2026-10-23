#!/bin/sh
# 重建暫時用的 CA 信任庫（CVE-2026-111943，eMudhra emSign 中繼 CA 外洩）
#   certs/        取自 alpine:latest（ca-certificates 20261020 起已移除 emSign ECC Root CA - G3 與 AAA Certificate Services）
#                 另拆出 <subject_hash>.N 檔供只讀 CApath 的程式使用
#   java/cacerts  questdb 內建 JDK 的 cacerts，刪除上述兩個 root
# 重建後需重建掛載它的容器（單檔 bind mount 會綁住舊 inode）
set -eu
cd "$(dirname "$0")"
umask 022

rm -rf certs.new && mkdir certs.new
docker run --rm alpine:latest cat /etc/ssl/certs/ca-certificates.crt > certs.new/ca-certificates.crt
awk '/BEGIN CERTIFICATE/{n++} n{print > sprintf("certs.new/tmp-%03d.pem", n)}' certs.new/ca-certificates.crt
for f in certs.new/tmp-*.pem; do
  h=$(openssl x509 -noout -subject_hash -in "$f"); i=0
  while [ -e "certs.new/$h.$i" ]; do i=$((i + 1)); done
  mv "$f" "certs.new/$h.$i"
done
if for f in certs.new/*.[0-9]; do openssl x509 -noout -subject -in "$f"; done \
  | grep -E 'emSign ECC Root CA - G3|AAA Certificate Services'; then
  echo "alpine:latest 仍含已撤銷信任的 root，中止" >&2; exit 1
fi
rm -rf certs && mv certs.new certs

mkdir -p java
docker run --rm --user "$(id -u):$(id -g)" --entrypoint sh -v "$PWD/java:/out" questdb/questdb:8.2.1 -c '
  cp /app/lib/security/cacerts /out/cacerts.new && chmod 644 /out/cacerts.new
  for a in emsigneccrootca-g3 "emsigneccrootcag3 [jdk]" "comodoaaaca [jdk]"; do
    /app/bin/keytool -delete -noprompt -storepass changeit -keystore /out/cacerts.new -alias "$a" 2>/dev/null || true
  done
  if /app/bin/keytool -list -v -storepass changeit -keystore /out/cacerts.new | grep -E "^Owner: CN=(emSign ECC Root CA - G3|AAA Certificate Services),"; then
    echo "cacerts 仍含已撤銷信任的 root，中止" >&2; exit 1
  fi'
mv java/cacerts.new java/cacerts
echo "certs: $(ls certs | wc -l) 檔，java/cacerts 已更新"

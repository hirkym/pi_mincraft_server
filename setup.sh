#!/usr/bin/env bash
set -Eeuo pipefail

readonly SERVER_DIR="/opt/minecraft-bedrock"
readonly SERVICE_NAME="minecraft-bedrock"
readonly BOX64_KEYRING="/usr/share/keyrings/box64-archive-keyring.gpg"

fail() {
  printf 'エラー: %s\n' "$*" >&2
  exit 1
}

if [[ "${EUID}" -ne 0 ]]; then
  fail "root権限で実行してください (例: sudo ./setup.sh)"
fi
[[ -r /etc/os-release ]] || fail "/etc/os-releaseを読み取れません。"
# shellcheck disable=SC1091
source /etc/os-release
case "${ID:-}" in
  debian|raspbian|ubuntu) ;;
  *) fail "Debian / Raspberry Pi OS / Ubuntu以外は対象外です (検出: ${PRETTY_NAME:-不明})" ;;
esac

machine="$(dpkg --print-architecture 2>/dev/null || uname -m)"
case "$machine" in
  arm64|aarch64) ;;
  *) fail "64-bit ARM OSが必要です (検出: ${machine})。Raspberry Pi OSの64-bit版を使用してください。" ;;
esac

command -v systemctl >/dev/null 2>&1 || fail "systemdが必要です。"
[[ -t 0 ]] || fail "EULA同意を確認できる端末から実行してください。"

cat <<'NOTICE'
Minecraft Bedrock Dedicated ServerのLinux x86_64版をBox64経由で実行します。
Raspberry Pi 3 B+ (1GB RAM)では性能や安定性に制約があり、Minecraft公式の
システム要件 (RAM 4GB) を満たしません。Linux版の公式サポート対象はUbuntuです。
NOTICE
read -r -p "Minecraft EULA (https://www.minecraft.net/eula) を確認し、同意しますか？ [y/N] " answer
case "$answer" in
  y|Y|yes|YES) ;;
  *) fail "EULAに同意しなかったため、セットアップを中止しました。" ;;
esac

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  ca-certificates curl gpg unzip libjemalloc2

# Box64 project documentation points Debian-based systems to this prebuilt package repository.
install -d -m 0755 /usr/share/keyrings
curl --http1.1 --retry 3 --retry-all-errors --connect-timeout 15 --max-time 60 -fsSL https://Pi-Apps-Coders.github.io/box64-debs/KEY.gpg \
  | gpg --dearmor --yes -o "$BOX64_KEYRING"
cat > /etc/apt/sources.list.d/box64.sources <<'BOX64_SOURCE'
Types: deb
URIs: https://Pi-Apps-Coders.github.io/box64-debs/debian
Suites: ./
Signed-By: /usr/share/keyrings/box64-archive-keyring.gpg
BOX64_SOURCE
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y box64-generic-arm
BOX64_BIN="$(command -v box64 || true)"
[[ -n "$BOX64_BIN" ]] || fail "Box64をインストールしましたが、box64コマンドがPATH上に見つかりません。"

if ! id minecraft >/dev/null 2>&1; then
  useradd --system --home-dir "$SERVER_DIR" --shell /usr/sbin/nologin minecraft
fi
install -d -o minecraft -g minecraft -m 0750 "$SERVER_DIR"

if [[ ! -x "$SERVER_DIR/bedrock_server" ]]; then
  if [[ "$#" -gt 1 ]]; then
    fail "使い方: sudo ./setup.sh [公式サーバーZIPのパス]"
  fi

  if [[ "$#" -eq 1 ]]; then
    server_zip="$1"
    [[ -r "$server_zip" ]] || fail "サーバーZIPを読み取れません: $server_zip"
    unzip -oq "$server_zip" -d "$SERVER_DIR"
  else
    download_page="$(mktemp)"
    server_zip="$(mktemp --suffix=.zip)"
    trap 'rm -f "$download_page" "$server_zip"' EXIT
    curl --http1.1 --retry 3 --retry-all-errors --connect-timeout 15 --max-time 90 \
      -fL https://www.minecraft.net/en-us/download/server/bedrock -o "$download_page"
    download_url="$(grep -Eo 'https://www\.minecraft\.net/bedrockdedicatedserver/bin-linux/bedrock-server-[0-9.]+\.zip' "$download_page" | sed -n '1p')"
    [[ -n "$download_url" ]] || fail "公式ダウンロードページからLinux版のURLを取得できませんでした。ZIPを引数に指定して再実行してください。"
    curl --http1.1 --retry 3 --retry-all-errors --connect-timeout 15 --max-time 300 \
      -fL "$download_url" -o "$server_zip"
    unzip -oq "$server_zip" -d "$SERVER_DIR"
  fi
  chown -R minecraft:minecraft "$SERVER_DIR"
  chmod u+x "$SERVER_DIR/bedrock_server"
else
  printf '既存のサーバーファイルを使用します。ワールドや設定は変更しません。\n'
fi

cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<UNIT
[Unit]
Description=Minecraft Bedrock Dedicated Server (Box64)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=minecraft
Group=minecraft
WorkingDirectory=${SERVER_DIR}
Environment=LD_LIBRARY_PATH=.
ExecStart=${BOX64_BIN} ./bedrock_server
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now "${SERVICE_NAME}.service"

printf '\nBox64経由でサーバーを起動しました。\n'
printf 'サーバーとワールドデータ: %s\n' "$SERVER_DIR"
printf '接続ポート: UDP 19132 (IPv4), UDP 19133 (IPv6)\n'
printf 'ログ確認: sudo journalctl -u %s -f\n' "$SERVICE_NAME"
printf '停止: sudo systemctl stop %s\n' "$SERVICE_NAME"

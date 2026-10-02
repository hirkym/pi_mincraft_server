# Raspberry Pi 3 B+ Minecraft 統合版サーバー

## 目的

このリポジトリは、Raspberry Pi 3 B+にMinecraft統合版（Bedrock Edition）のサーバーを構築することを目的としています。構築に必要な設定や手順をまとめます。

## セットアップ

64-bit版のRaspberry Pi OSを起動し、このリポジトリのディレクトリで次を実行します。

```sh
sudo ./setup.sh
```

スクリプトはBox64と公式Linux版Bedrockサーバーを導入し、systemdサービスとして起動します。初回実行時にMinecraft EULAへの同意を確認します。サーバー、ワールド、設定は`/opt/minecraft-bedrock`に保存されます。

> Raspberry Pi 3 B+ではARM64上でBox64を使ってx86_64版サーバーを実行します。メモリは1GBで、Minecraft公式のシステム要件に記載された4GBを下回るため、性能や安定性に制約があります。

# gateway

WSL/NixOSからzmxセッションを選択・attachするgateway flake

## 観測ログ

`GW_BACKEND_CALL` 環境でbackend呼び出しを観測可能：

```bash
./result/bin/gateway --session <name> 2>&1 | grep GW_BACKEND_CALL
```

## 使用方法

```bash
# ローカル開発（path-basedでも安全：zmxHeadをビルドしない）
nix run ~/repos/gateway-remote#gateway

# flake refベースも同様
nix run .#gateway

# GitHubから（push後）
nix run github:t-takazawa/gateway-remote#gateway
```

**安全性の根拠**: `gateway` は `zmx` を build dependency として持たず、PATH解決のみ。`nix run` で zmx HEAD をビルドすることは **ありません**。

## 初回セットアップ（zmx HEAD のインストール）

`gateway` は **実行時に `zmx` をPATHから参照**します（build時ではない）。初回のみ以下を実行：

```bash
# WSL内のNixOSで実行
sudo nix build ~/repos/gateway-remote#zmxHead --option sandbox false -o ~/.cache/zmxHead

# zmx を PATH に symlink
mkdir -p ~/.local/bin
ln -sf ~/.cache/zmxHead/bin/zmx ~/.local/bin/zmx

# 確認
zmx --version
# zmx 0.2.0
```

**注意**: `zmxHead` のbuildにはネットワークアクセスが必要（Nix sandboxを無効化）。一度buildすれば以降は `nix run .#gateway` だけでOK。

## オプション

```bash
nix run .#gateway -- --session <session-name>
```

## 構成

- `flake.nix`: Nix flake定義（gateway app + テスト）
- `backends/zmx-local/`: WSL内zmx backend（list/attachを提供）
- `backends/zmx-remote/`: SSH経由zmx backend（TODO: Phase4）
- `flake.lock`: 依存ロックファイル

### 関連 flake

- `repo-sessions`: `$HOME/repos` からrepo選択 → zmx attach → tool起動
  - **⚠️  注意**: `nix run ~/repos/gateway-remote#repo-sessions` は **ショートカット** です
  - 正本は `~/repos/repo-sessions` です（テスト/設定はそっちで完結）
  - 詳細は `~/repos/repo-sessions/README.md`

### ディレクトリ構成について

Phase3で `backends/zmx-local/` を分離しました。`backends/shared/` は **重複が実在したら作成** します（YAGNI防止）。

### リモートホストでの zmx HEAD インストール

`zmx-remote` backend を使う場合、リモートホストでも zmx HEAD が必要：

```bash
# リモートホスト（NixOS）で実行
ssh <host> "mkdir -p ~/.cache && nix build <path-to-gateway-remote>#zmxHead --option sandbox false -o ~/.cache/zmxHead"
ssh <host> "mkdir -p ~/.local/bin && ln -sf ~/.cache/zmxHead/bin/zmx ~/.local/bin/zmx"
ssh <host> "zmx --version"  # zmx 0.2.0 と表示されればOK
```

### 断言コマンド

```bash
# apps-wireup: --help が Usage を表示するか検証
nix build .#checks.x86_64-linux.apps-wireup

# bb-red-session-attach: --session 時に stderr に GW_BACKEND_CALL が出るか検証
nix build .#checks.x86_64-linux.bb-red-session-attach

# forbid-direct-zmx: gateway が zmx を直接呼ばず backend 経由か検証
nix build .#checks.x86_64-linux.forbid-direct-zmx

# zmx-local-list: zmx-local list が zmx list を呼ぶか検証
nix build .#checks.x86_64-linux.zmx-local-list

# zmx-local-attach: zmx-local attach <session> が zmx attach <session> を呼ぶか検証
nix build .#checks.x86_64-linux.zmx-local-attach

# zmxHead-explicit-only: gateway が zmxHead をビルド/依存しないことを検証
nix build .#checks.x86_64-linux.zmxHead-explicit-only
```

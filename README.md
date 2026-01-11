# gateway

WSL/NixOSからzmxセッションを選択・attachするgateway flake

## 観測ログ

`GW_BACKEND_CALL` 環境でbackend呼び出しを観測可能：

```bash
nix run .#gateway -- --session <name> 2>&1 | grep GW_BACKEND_CALL
```

## 使用方法

```bash
# session一覧確認
nix run .#gateway -- --list

# 特定sessionにattach
nix run .#gateway -- --session <name>

# GitHubから（push後）
nix run github:<owner>/<repo>#gateway -- --session <name>
```

**安全性の根拠**: `gateway` は `zmx` を build dependency として持たず、PATH解決のみ。`nix run` で zmx HEAD をビルドすることは **ありません**。

## 初回セットアップ（zmx HEAD のインストール）

`gateway` は **実行時に `zmx` をPATHから参照**します（build時ではない）。初回のみ以下を実行：

```bash
# WSL内のNixOSで実行
sudo nix build .#zmxHead --option sandbox false -o ~/.cache/zmxHead

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
--help     Show this help message
--list     List sessions (with optional --prefix filter)
--session  Attach to a specific session (required)
--prefix   Filter sessions by prefix (for --list)
```

## 構成

- `flake.nix`: Nix flake定義（gateway app + テスト）
- `backends/zmx-local/`: WSL内zmx backend（list/attachを提供）
- `backends/zmx-remote/`: SSH経由zmx backend（list/attachを提供）
- `flake.lock`: 依存ロックファイル

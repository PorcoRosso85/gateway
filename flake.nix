{
  description = "gateway: zmx session selection + attach for Windows + WSL";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    zmx.url = "github:neurosnap/zmx?rev=16d66af23d66b5d060d16f817debbfd545e0dd0e";
    repo-sessions.url = "path:/home/nixos/repos/repo-sessions";
    repo-sessions.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      zmx,
      repo-sessions,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      lib = nixpkgs.lib;
    in
    {
      packages = lib.genAttrs systems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          zmxPkg = zmx.packages.${system}.zmx or zmx.packages.${system}.default;
          zmx-local = import ./backends/zmx-local { inherit pkgs zmxPkg; };
          zmx-remote = import ./backends/zmx-remote { inherit pkgs zmxPkg; };
        in
        {
          inherit zmx-local zmx-remote zmxPkg;
          zmx = zmxPkg;
          zmxHead = zmxPkg.overrideAttrs (old: {
            buildPhase = (old.buildPhase or "") + ''
              # Fix EXDEV: Put Zig cache and TMPDIR in same mount point
              export TMPDIR="$TMPDIR"
              export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-cache"
              export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-cache"
            '';
          });
          gateway = pkgs.writeShellApplication {
            name = "gateway";
            runtimeInputs = [ ];
            text = ''
              #!/usr/bin/env bash
              set -euo pipefail

              GW_BACKEND="${zmx-local}/bin/zmx-local"
              GW_PREFIX=""
              GW_SESSION=""
              GW_LIST=""

              _gateway_backend_attach() {
                local session="$1"
                echo "GW_BACKEND_CALL=attach session=$session" >&2
                exec "$GW_BACKEND" attach "$session"
              }

              _gateway_backend_list() {
                "$GW_BACKEND" list
              }

              if [[ $# -gt 0 && "$1" == "--help" ]]; then
                echo "Usage: gateway [OPTIONS]"
                echo "Options:"
                echo "  --help     Show this help message"
                echo "  --list     List sessions (with optional --prefix filter)"
                echo "  --session  Attach to a specific session (required)"
                echo "  --prefix   Filter sessions by prefix (for --list)"
                exit 0
              fi

              while [[ $# -gt 0 ]]; do
                case "$1" in
                  --list)
                    GW_LIST="1"
                    shift
                    ;;
                  --prefix)
                    GW_PREFIX="$2"
                    shift 2
                    ;;
                  --session)
                    GW_SESSION="$2"
                    shift 2
                    ;;
                  *)
                    echo "Unknown option: $1" >&2
                    exit 1
                    ;;
                esac
              done

              if [[ -n "$GW_LIST" ]]; then
                _gateway_backend_list | grep -E "^''${GW_PREFIX}"
                exit 0
              fi

              if [[ -z "$GW_SESSION" ]]; then
                echo "Error: --session is required (use --list to see available sessions)" >&2
                exit 1
              fi

              _gateway_backend_attach "$GW_SESSION"
            '';
          };
        }
      );

      apps = lib.genAttrs systems (system: {
        gateway = {
          type = "app";
          program = "${self.packages.${system}.gateway}/bin/gateway";
        };
        repo-sessions = repo-sessions.apps.${system}.repo-sessions;
        default = self.apps.${system}.gateway;
      });

      checks = lib.genAttrs systems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          gatewayApp = self.packages.${system}.gateway;
          zmxPkg = zmx.packages.${system}.zmx or zmx.packages.${system}.default;
          zmxLocal = self.packages.${system}.zmx-local;
          zmxRemote = self.packages.${system}.zmx-remote;
        in
        {
          apps-wireup = pkgs.stdenv.mkDerivation {
            name = "test-apps-wireup";
            src = self;
            dontBuild = true;
            dontConfigure = true;
            dontUnpack = true;
            installPhase = ''
              SCRIPT=${gatewayApp}/bin/gateway
              OUTPUT=$($SCRIPT --help 2>&1 || true)
              if echo "$OUTPUT" | grep -q "Usage: gateway"; then
                echo "PASS: apps-wireup"
                touch $out
              else
                echo "FAIL: apps-wireup - help output not found"
                echo "Output was: $OUTPUT"
                exit 1
              fi
            '';
          };

          bb-red-session-attach = pkgs.stdenv.mkDerivation {
            name = "test-bb-red-session-attach";
            src = self;
            dontBuild = true;
            dontConfigure = true;
            dontUnpack = true;
            installPhase = ''
                            mkdir -p $out/bin
                            cat > $out/bin/zmx << 'MOCK_ZMX'
              #!/bin/sh
              echo "zmx $*" >&2
              exit 0
              MOCK_ZMX
                            chmod +x $out/bin/zmx

                                          SCRIPT=${gatewayApp}/bin/gateway
                                          PATH="$out/bin:$PATH" STERR=$($SCRIPT --session test-session 2>&1 || true)
                                          if echo "$STERR" | grep -q "GW_BACKEND_CALL=attach session=test-session"; then
                                            echo "PASS: bb-red-session-attach"
                                            touch $out/passed
                                          else
                                            echo "FAIL: bb-red-session-attach - GW_BACKEND_CALL not found in stderr"
                                            echo "stderr was: $STERR"
                                            exit 1
                                          fi
            '';
          };

          forbid-direct-zmx = pkgs.stdenv.mkDerivation {
            name = "test-forbid-direct-zmx";
            src = self;
            dontBuild = true;
            dontConfigure = true;
            dontUnpack = true;
            installPhase = ''
              GATEWAY_SCRIPT=${gatewayApp}/bin/gateway
              if grep -E '^\s*(exec\s+)?zmx\s' "$GATEWAY_SCRIPT" > /dev/null 2>&1; then
                echo "FAIL: forbid-direct-zmx - gateway calls zmx directly (use backend dispatch instead)"
                grep -n -E '^\s*(exec\s+)?zmx\s' "$GATEWAY_SCRIPT" || true
                exit 1
              fi
              if grep -E 'GW_BACKEND.*zmx[^l-]' "$GATEWAY_SCRIPT" > /dev/null 2>&1; then
                echo "FAIL: forbid-direct-zmx - GW_BACKEND set to zmx directly (use zmx-local or zmx-remote)"
                exit 1
              fi
              echo "PASS: forbid-direct-zmx - no direct zmx calls found"
              touch $out
            '';
          };

          zmx-local-list = pkgs.stdenv.mkDerivation {
            name = "test-zmx-local-list";
            src = self;
            dontBuild = true;
            dontConfigure = true;
            dontUnpack = true;
            installPhase = ''
                            mkdir -p $out/bin
                            cat > $out/bin/zmx << 'MOCK_ZMX'
              #!/bin/sh
              echo "session-1"
              echo "session-2"
              MOCK_ZMX
                            chmod +x $out/bin/zmx

                            BACKEND=${zmxLocal}/bin/zmx-local
                            PATH="$out/bin:$PATH" OUTPUT=$($BACKEND list 2>&1 || true)
                            if echo "$OUTPUT" | grep -q "session-1" && echo "$OUTPUT" | grep -q "session-2"; then
                              echo "PASS: zmx-local-list"
                              touch $out
                            else
                              echo "FAIL: zmx-local-list - expected session list"
                              echo "Output was: $OUTPUT"
                              exit 1
                            fi
            '';
          };

          zmx-local-attach = pkgs.stdenv.mkDerivation {
            name = "test-zmx-local-attach";
            src = self;
            dontBuild = true;
            dontConfigure = true;
            dontUnpack = true;
            installPhase = ''
                            mkdir -p $out/bin
                            cat > $out/bin/zmx << 'MOCK_ZMX'
              #!/bin/sh
              echo "zmx $*" >&2
              exit 0
              MOCK_ZMX
                            chmod +x $out/bin/zmx

                                          BACKEND=${zmxLocal}/bin/zmx-local
                                          PATH="$out/bin:$PATH" OUTPUT=$($BACKEND attach test-session 2>&1 || true)
                                          if echo "$OUTPUT" | grep -q "zmx attach test-session"; then
                                            echo "PASS: zmx-local-attach"
                                            touch $out
                                          else
                                            echo "FAIL: zmx-local-attach - zmx attach not called"
                                            echo "Output was: $OUTPUT"
                                            exit 1
                                          fi
            '';
          };

          zmx-remote-list = pkgs.stdenv.mkDerivation {
            name = "test-zmx-remote-list";
            src = self;
            dontBuild = true;
            dontConfigure = true;
            dontUnpack = true;
            installPhase = ''
                            mkdir -p $out/bin
                            cat > $out/bin/ssh << 'MOCK_SSH'
              #!/bin/sh
              echo "SSH_ARGV: ssh $*" >&2
              MOCK_SSH
                            chmod +x $out/bin/ssh

                                          BACKEND=${zmxRemote}/bin/zmx-remote
                                          export REMOTE_HOST=test-host
                                          export PATH="$out/bin:$PATH"
                                          STDOUT=$($BACKEND list 2>&1 || true)
                                          SSH_ARGS=$(echo "$STDOUT" | grep "SSH_ARGV:" | sed 's/SSH_ARGV: //' || true)
                                          if echo "$SSH_ARGS" | grep -q "ssh.*-T.*test-host.*--.*zmx.*list"; then
                                            echo "PASS: zmx-remote-list"
                                            touch $out
                                          else
                                            echo "FAIL: zmx-remote-list - expected 'ssh -T <host> -- zmx list'"
                                            echo "SSH args were: $SSH_ARGS"
                                            echo "Full output was: $STDOUT"
                                            exit 1
                                          fi
            '';
          };

          zmx-remote-attach = pkgs.stdenv.mkDerivation {
            name = "test-zmx-remote-attach";
            src = self;
            dontBuild = true;
            dontConfigure = true;
            dontUnpack = true;
            installPhase = ''
                            mkdir -p $out/bin
                            cat > $out/bin/ssh << 'MOCK_SSH'
              #!/bin/sh
              echo "SSH_ARGV: ssh $*" >&2
              MOCK_SSH
                            chmod +x $out/bin/ssh

                                          BACKEND=${zmxRemote}/bin/zmx-remote
                                          export REMOTE_HOST=test-host
                                          export PATH="$out/bin:$PATH"
                                          STDOUT=$($BACKEND attach test-session 2>&1 || true)
                                          SSH_ARGS=$(echo "$STDOUT" | grep "SSH_ARGV:" | sed 's/SSH_ARGV: //' || true)
                                          if echo "$SSH_ARGS" | grep -q "ssh.*-T.*test-host.*--.*zmx.*attach.*test-session"; then
                                            echo "PASS: zmx-remote-attach"
                                            touch $out
                                          else
                                            echo "FAIL: zmx-remote-attach - expected 'ssh -T <host> -- zmx attach <session>'"
                                            echo "SSH args were: $SSH_ARGS"
                                            echo "Full output was: $STDOUT"
                                            exit 1
                                          fi
            '';
          };

          zmxHead-explicit-only = pkgs.stdenv.mkDerivation {
            name = "test-zmxHead-explicit-only";
            src = self;
            dontBuild = true;
            dontConfigure = true;
            dontUnpack = true;
            installPhase = ''
              GATEWAY_SCRIPT=${gatewayApp}/bin/gateway

              if grep -E 'zmxHead|zmx[^l-]' "$GATEWAY_SCRIPT" > /dev/null 2>&1; then
                echo "FAIL: zmxHead-explicit-only - gateway script references zmx directly"
                grep -n -E 'zmxHead|zmx[^l-]' "$GATEWAY_SCRIPT" || true
                exit 1
              fi

              if grep -E 'runtimeInputs.*\[.*zmx.*\]' flake.nix | grep -v '^#' > /dev/null 2>&1; then
                echo "FAIL: zmxHead-explicit-only - gateway has zmx in runtimeInputs"
                exit 1
              fi

              echo "PASS: zmxHead-explicit-only - gateway does not directly reference zmx/zmxHead"
              touch $out
            '';
          };

          list-filter-by-prefix = pkgs.stdenv.mkDerivation {
            name = "test-list-filter-by-prefix";
            src = self;
            dontBuild = true;
            dontConfigure = true;
            dontUnpack = true;
            installPhase = ''
              mkdir -p $out/bin
              cat > $out/bin/zmx << 'MOCK_ZMX'
              #!/bin/sh
              echo "prefix-session1"
              echo "prefix-session2"
              echo "other-session"
              MOCK_ZMX
              chmod +x $out/bin/zmx

              BACKEND=${zmxLocal}/bin/zmx-local
              export PATH="$out/bin:$PATH"

              GATEWAY=${gatewayApp}/bin/gateway
              OUTPUT=$($GATEWAY --list --prefix "prefix" 2>&1 || true)

              if echo "$OUTPUT" | grep -q "prefix-session1" && \
                 echo "$OUTPUT" | grep -q "prefix-session2" && \
                 ! echo "$OUTPUT" | grep -q "other-session"; then
                echo "PASS: list-filter-by-prefix - prefix filter works"
                touch $out
              else
                echo "FAIL: list-filter-by-prefix - grep filter not working correctly"
                echo "filter output was: $OUTPUT"
                exit 1
              fi
            '';
          };

          forbid-fzf = pkgs.stdenv.mkDerivation {
            name = "test-forbid-fzf";
            src = self;
            dontBuild = true;
            dontConfigure = true;
            dontUnpack = true;
            installPhase = ''
              GATEWAY_SCRIPT=${gatewayApp}/bin/gateway

              # Check that fzf is not referenced anywhere in gateway
              if grep -R "\bfzf\b" $GATEWAY_SCRIPT; then
                echo "FAIL: forbid-fzf - fzf string found in gateway script"
                exit 1
              fi

              echo "PASS: forbid-fzf - fzf not referenced in gateway"
              touch $out
            '';
          };
        }
      );
    };
}

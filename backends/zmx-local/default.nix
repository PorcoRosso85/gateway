{ pkgs, zmxPkg }:
# NOTE: zmxPkg is NOT a build dependency - zmx-local expects zmx to be in PATH at runtime
# This prevents "nix run gateway" from triggering zmx HEAD build
pkgs.writeShellApplication {
  name = "zmx-local";
  runtimeInputs = [ ];
  text = builtins.readFile ./bin/zmx-local;
}

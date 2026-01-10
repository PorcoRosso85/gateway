{ pkgs, zmxPkg }:
pkgs.writeShellApplication {
  name = "zmx-remote";
  runtimeInputs = [ ];
  text = builtins.readFile ./bin/zmx-remote;
}

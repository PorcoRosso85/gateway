{ pkgs, zmxPkg }:
pkgs.writeShellApplication {
  name = "zmx-remote";
  runtimeInputs = [ zmxPkg pkgs.openssh ];
  text = builtins.readFile ./bin/zmx-remote;
}

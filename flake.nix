{
  description = "RemindMeet: full-screen reminder one minute before each meeting";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { nixpkgs, ... }:
    {
      packages.aarch64-darwin.default =
        nixpkgs.legacyPackages.aarch64-darwin.callPackage ./package.nix
          { };
    };
}

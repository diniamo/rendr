with import <nixpkgs> {}; mkShell {
  packages = [
    odin
    ols
    nnd
    hyperfine

    raylib
  ];
}

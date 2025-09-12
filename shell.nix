with import <nixpkgs> {}; mkShellNoCC {
  packages = [
    odin
    ols
    lldb
    hyperfine
  ];
}

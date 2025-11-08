with import <nixpkgs> {}; mkShell {
  packages = [
    odin
    ols
    nnd
    hyperfine

    glfw
    vulkan-validation-layers
    glslang
    renderdoc
  ];
}

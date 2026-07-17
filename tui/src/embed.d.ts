// `import x from "./foo.tar.gz" with { type: "file" }` yields the embedded file's
// path string (real path in dev, `$bunfs/...` in the compiled binary).
declare module "*.tar.gz" {
  const path: string
  export default path
}

// Same for the tree-sitter grammar + query assets: importing them as files makes
// `bun --compile` embed them into the single-file binary. A bare
// `new URL(..., import.meta.url)` is NOT bundled, so the wasm would be missing at
// runtime in the packaged CLI.
declare module "*.wasm" {
  const path: string
  export default path
}
declare module "*.scm" {
  const path: string
  export default path
}

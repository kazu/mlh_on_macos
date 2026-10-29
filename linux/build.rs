use std::path::PathBuf;

fn main() {
    let root = PathBuf::from(std::env::var_os("CARGO_MANIFEST_DIR").unwrap());
    let library = std::env::var_os("MLH_BRIDGE_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| root.join("../.build/debug"));
    println!("cargo:rerun-if-env-changed=MLH_BRIDGE_DIR");
    println!("cargo:rustc-link-search=native={}", library.display());
    println!("cargo:rustc-link-lib=dylib=MLHBridge");
    println!("cargo:rustc-link-arg=-Wl,-rpath,$ORIGIN/../lib/mlh");
}

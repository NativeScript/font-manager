fn main() {
    // the runtime soname, so no fontconfig dev package is needed to link
    println!("cargo:rustc-link-lib=dylib:+verbatim=libfontconfig.so.1");
    println!("cargo:rustc-cdylib-link-arg=-Wl,-soname,libfontmanager.so");
}

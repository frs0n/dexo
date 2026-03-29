#!/bin/zsh
# Build DohProxyFFI.xcframework for iOS (device + simulator)
# Usage: ./scripts/build-ios.sh [debug|release]

set -e

build_type="${1:-release}"
script_dir=$(cd "$(dirname "$0")"; pwd)
package_dir=$(cd "$script_dir/.."; pwd)

cd "$package_dir"

# aws-lc-rs (used by the ech feature) compiles C/asm targeting the host SDK version.
# Setting IPHONEOS_DEPLOYMENT_TARGET avoids linker errors about newer-than-linked symbols.
export IPHONEOS_DEPLOYMENT_TARGET=16.0

echo "Building doh_proxy for aarch64-apple-ios (${build_type})..."
cargo build --profile="$build_type" --target aarch64-apple-ios --features ech

echo "Building doh_proxy for aarch64-apple-ios-sim (${build_type})..."
cargo build --profile="$build_type" --target aarch64-apple-ios-sim --features ech

echo "Building doh_proxy for x86_64-apple-ios (${build_type})..."
cargo build --profile="$build_type" --target x86_64-apple-ios --features ech

echo "Creating fat simulator library..."
mkdir -p "target/ios-sim-fat/${build_type}"
lipo -create \
  "target/aarch64-apple-ios-sim/${build_type}/libdoh_proxy.a" \
  "target/x86_64-apple-ios/${build_type}/libdoh_proxy.a" \
  -output "target/ios-sim-fat/${build_type}/libdoh_proxy.a"

HEADER="Sources/CDohProxy/include"
OUT="Artifacts/DohProxyFFI.xcframework"

echo "Creating xcframework..."
mkdir -p Artifacts
rm -rf "$OUT"

xcodebuild -create-xcframework \
  -library "target/aarch64-apple-ios/${build_type}/libdoh_proxy.a" \
  -headers "${HEADER}" \
  -library "target/ios-sim-fat/${build_type}/libdoh_proxy.a" \
  -headers "${HEADER}" \
  -output "$OUT"

echo "Done: $OUT"

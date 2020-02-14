#!/bin/bash

# Build a Linux binary on macOS using Docker
# https://github.com/emk/rust-musl-builder

if ! [ -x "$(command -v docker)" ]; then
  echo 'Error: docker is not installed.' >&2
  exit 1
fi

docker run --rm -it -v "$(pwd)":/home/rust/src ekidd/rust-musl-builder:nightly-2020-01-26-openssl11 cargo build --release

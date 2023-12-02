# Basalt
[![License: MIT](https://img.shields.io/badge/License-MIT-darkgoldenrod.svg)](https://opensource.org/licenses/MIT) [![Minecraft Version: 1.20.2](https://img.shields.io/badge/Minecraft_Version-1.20.2-steelblue)](https://minecraft.wiki/w/Java_Edition_1.20.2) ![Protocol Version: 764](https://img.shields.io/badge/Protocol_Version-764-seagreen)

A performant, drop-in replacement for the vanilla Minecraft server, written in Rust

> [!WARNING] <p align="center"><strong>Basalt is in very early development. As such, many features will be incomplete.</strong></p>

## Usage
Binaries are not yet distributed for Basalt, so you need to [build it from source](#Building).

Copy the `basalt` binary to your server directory, and run it. Basalt behaves (almost) identically
to the vanilla Minecraft server, so vanilla configs and worlds will work out of the box.

### Building
```sh
git clone https://github.com/abachrati/basalt
cd basalt
cargo build --release
```
then copy `target/release/basalt` to your server directory.

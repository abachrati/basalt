# Basalt
[![License: MIT](https://img.shields.io/badge/License-MIT-darkgoldenrod.svg)](https://opensource.org/licenses/MIT)

A performant, drop-in replacement for the vanilla Minecraft server, written in Zig

> [!WARNING] <p align="center"><strong>Basalt is in very early development. As such, many features will be incomplete.</strong></p>

## Usage
Binaries are not yet distributed for Basalt, so you need to [build it from source](#Building).

Copy the `basalt` binary to your server directory, and run it. Basalt behaves (almost) identically
to the vanilla Minecraft server, so vanilla configs and worlds will work out of the box.

### Building
```sh
git clone https://github.com/abachrati/basalt
cd basalt
zig build
```
then copy `zig-out/bin/basalt` to your server directory.

# inject-o

A CLI tool for injecting dependent dylibs into the Mach-O file.

<!-- # Badges -->

[![Github issues](https://img.shields.io/github/issues/swiftbin/inject-o)](https://github.com/swiftbin/inject-o/issues)
[![Github forks](https://img.shields.io/github/forks/swiftbin/inject-o)](https://github.com/swiftbin/inject-o/network/members)
[![Github stars](https://img.shields.io/github/stars/swiftbin/inject-o)](https://github.com/swiftbin/inject-o/stargazers)
[![Github top language](https://img.shields.io/github/languages/top/swiftbin/inject-o)](https://github.com/swiftbin/inject-o/)

## Usage

```
OVERVIEW: Inject dependent dylibs into the Mach-O file

USAGE: inject-o <input-path> --dylib <dylib> [--output <output>] [--weak] [--upward] [--quiet]

ARGUMENTS:
  <input-path>            Path to the input Mach-O file.

OPTIONS:
  -d, --dylib <dylib>     Path to the dylib to be added
  -o, --output <output>   Path to the output Mach-O file (default:
                          <input>.injected)
  -w, --weak              Add as LC_LOAD_WEAK_DYLIB
  -u, --upward            Add as LC_LOAD_UPWARD_DYLIB
  --quiet                 Suppress all output.
  --version               Show the version.
  -h, --help              Show help information.
```

## License

inject-o is released under the MIT License. See [LICENSE](./LICENSE)

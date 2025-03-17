# Iced - Alpine powered coldbrew

Iced is a "brew" style package manager for Linux distributions that offers
the full power of the Alpine Linux aports repository with no root access
required.

## Installation

Iced depends on mkosi-sandbox, this may be part of the `mkosi` package in
your distro, or can be obtained from [the mkosi git
repository](https://github.com/systemd/mkosi).

Then install iced with:

```sh
git clone https://github.com/calebccff/iced
ln -s $PWD/iced/iced ~/.local/bin/iced
```

Ensure that `~/.local/bin/` is in your PATH!

## Usage

All packages from the Alpine edge branch are available, though be wary that they
may not all function correctly.

Packages can be installed with `iced install`, and tools can be run with
`iced run`. If desired, a wrapper program can be installed to `~/.local/bin/`
with `iced wrap PROG`.

```shell-session
$ iced install cowsay
Installing cowsay
Installed binary /usr/bin/cowsay
Installed binary /usr/bin/cowthink

$ iced run cowsay Hi from Iced!
 __________________ 
< Hi from Iced! >
 ------------------ 
        \   ^__^
         \  (oo)\_______
            (__)\       )\/\
                ||----w |
                ||     ||

$ iced wrap cowsay
$ cowsay hello
```

Tools are by default run inside a chroot, utilising mkosi-sandbox. Your home
directory remains accessible, but other directories in your filesystem are not.

You may execute tools in the context of your host filesystem by invoking iced
with the `-c` flag, but note that the program won't be able to access any config
files or resources that it might expect to be available in the root filesystem.
This also doesn't work for scripts since programs are fed directly into the musl
dynamic linker.

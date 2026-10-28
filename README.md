# artix-nemesis

Post-install setup scripts for an [Artix Linux](https://artixlinux.org) (OpenRC)
desktop running [dwm](https://github.com/zythros/dwm) under LightDM.

Each numbered script does one job, is safe to re-run, and can be run on its
own or through the fzf menu. Packages come from the official Artix/Arch repos;
the AUR (via Chaotic AUR) is opt-in and nothing here requires it.

> Read a script before you run it. They use sudo and change system files.

## Quick start

On a fresh Artix OpenRC install, logged in as your normal user (with sudo):

```sh
git clone https://github.com/zythros/artix-nemesis.git
cd artix-nemesis
./menu-fzf.sh
```

Pick scripts with TAB, then press ENTER. They run in number order. For a
minimal desktop, run **800 → 802**, then reboot and choose the dwm
session in LightDM.

## Scripts

`./menu-fzf.sh --list` prints this list from the scripts themselves:

| Script | Group | What it does |
|---|---|---|
| `800-base-desktop.sh` | core | Xorg, LightDM and D-Bus. Skip it if your install already boots to a login screen |
| `801-chaotic-aur-setup.sh` | optional | Chaotic AUR repo + yay; also adds Arch `[extra]` |
| `802-dwm-setup.sh` | core | Builds zythros/dwm and zythros/dmenu (Mod+d launcher via j4-dmenu-desktop), adds the LightDM session, turns off screen blanking, sets JetBrains Mono Nerd Font as the default monospace font, makes dark mode the system default |
| `803-apps-setup.sh` | core | Apps from the `APPS` list at the top of the script, plus their config fixups |
| `810-wallpaper-setup.sh` | core | `wallpaper.sh` cycler + zythros/wallpaper images (Mod+w / Mod+Shift+w) |
| `830-slstatus-setup.sh` | core | Builds zythros/slstatus for the dwm bar |
| `836-printer-setup.sh` | hardware | CUPS, Avahi, SANE, plus a network Epson ET-3950 |
| `837-rgb-setup.sh` | hardware | OpenRGB, with a static colour applied at every boot |
| `840-snapper-setup.sh` | optional | Snapper + grub-btrfs (only runs on btrfs root with GRUB) |
| `870-vm-clipboard-setup.sh` | optional | SPICE clipboard sharing (only runs inside a VM) |
| `880-nvidia-bm-setup.sh` | hardware | NVIDIA drivers + Xorg config for a dual-GPU host |
| `881-nvidia-vm-setup.sh` | hardware | NVIDIA drivers inside a VM with a passed-through GPU |
| `890-vfio-passthrough.sh` | hardware | Binds a second GPU to vfio-pci for VM passthrough |
| `895-virt-manager-setup.sh` | optional | QEMU/KVM, libvirt and virt-manager |
| `896-distrobox-setup.sh` | optional | Rootless podman + distrobox |

**Groups.** *core* builds the desktop. *optional* scripts are general-purpose
extras. *hardware* scripts are written for one particular machine. Before
running one, check its settings block (the variables right after the header):
printer IP and model, RGB colour and zones, GPU model strings.

**Order.** Scripts run in number order, which respects their dependencies:

- 800 must come before 802, because 802 needs Xorg and LightDM.
- 801 must come before 802 if you want mullvad-browser on Mod+m (Chaotic AUR only).
- 802 must come before 810 and 830, which extend the dwm setup.
- 890 must come before 895 if you want GPU passthrough.
- 836 needs 801 for the Epson driver, which is AUR-only and pre-built in
  Chaotic AUR. Without 801, everything else in 836 still installs.
- 836, 837, 880 and 881 add Arch's `[extra]` repo themselves if it's missing
  (`openrgb`, `gscan2pdf` and the NVIDIA packages live there).

## Running scripts

```sh
./menu-fzf.sh                 # pick with fzf
./menu-fzf.sh --list          # show the menu
./menu-fzf.sh --run 800 802   # run these in order, no prompts
./802-dwm-setup.sh            # or run one directly
```

A script exits non-zero if any step failed. It ends with a list of every
warning and error, so nothing gets lost in the scroll. The menu shows a
pass/fail summary and exits non-zero if any script failed. Set `DEBUG=true`
to pause before each script starts.

## Standalone utilities (not in the menu)

- `kernel-rollback.sh`: pick an older `linux` + `linux-headers` pair from the
  pacman cache with fzf, install it and rebuild DKMS modules.
- `chaotic-aur-removal.sh`: undo 801 (removes Chaotic AUR, yay/paru, and
  packages installed from it).

## Writing a script

Copy the header of an existing script. `# Menu` and `# Group` are what put
it in the menu; leave out `# Menu` to keep a script off it. Then use the
helpers in `lib.sh`:

```bash
source "$(dirname "$(readlink -f "$0")")/lib.sh"
script_start "Setting up foo"    # DEBUG pause, banner, sudo keepalive
section "Packages"
ensure_pkgs foo foo-openrc       # installs what's missing; err() on failure
enable_service food              # rc-update add + start
some_step || err "what failed"   # recorded, script carries on
some_step || die "can't go on"   # recorded, script exits 1
script_done                      # "done" banner; print a summary after it
```

Also available: `ok`, `info`, `warn`, `pkg_sync`, `nohook_regen` (call it
after adding a repo to `pacman.conf`), `git_sync`, `make_install` and
`script_skip`.

pacman runs through a temporary config that masks the few post-install hooks
that hang on OpenRC: they try to reach a D-Bus session as root. All other
hooks still run. `lib.sh` explains the details.

## Related repos

The scripts build these forks from source:

- [zythros/dwm](https://github.com/zythros/dwm): keybindings live in its `config.h`
- [zythros/dmenu](https://github.com/zythros/dmenu)
- [zythros/slstatus](https://github.com/zythros/slstatus)

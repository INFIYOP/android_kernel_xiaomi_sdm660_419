# Aroma installer (Tulip)

`make-aroma-zip.sh` turns a normal `Image.gz-dtb` into a second flashable zip
with a touch menu for the options this kernel already has built in:

| Menu option | What it does | Mechanism |
|---|---|---|
| CPU OC 2.2 / 2.4 GHz | `overclock.cpu=1/2` | kernel cmdline (`init/main.c`, `clk-cpu-osm-660.c`) |
| GPU OC 630 MHz | `overclock.gpu=1` | cmdline, `qcom,gpu-pwrlevel-binsoc` in the dtb |
| CPU UC 1.4 / 1.8 GHz | `underclock.cpu=1/2` | cmdline |
| zram size 1-6 GB | `zram.resize=N` | cmdline (kernel still caps it at half of RAM) |
| UV / OV per cluster | `qcom,custom-voltage-reduce/increase` | dtb patch (fdtput) |
| EAS energy model | 1 = built-in CAF table (default, no change); 2-4 = kdrag0n / hypeartist | dtb patch |

Every screen that is skipped means "no change", and the cmdline switches are
rewritten on every flash, so flashing again with "No" clears an earlier choice.

Notes
- The dtb patches need the DTB split from the kernel; the script does that
  by cutting `Image.gz-dtb` at the end of the gzip stream and refuses if more
  than one DTB is appended.
- Aroma binary, theme and the fdtput tool come from San-Kernel's public Veil
  Tulip release, pinned by sha256 in the script. Use `-b <zip>` offline.
- With Hyper (2.4 GHz) keep the CAF energy model: the alternative tables stop
  at 1.8-2.2 GHz.
- Aroma flow and fdt patches: San-Kernel (@user_why_red). AROMA Installer:
  amarullz. AnyKernel3: osm0sis.

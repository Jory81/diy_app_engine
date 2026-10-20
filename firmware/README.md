# Ready-made firmware (multi-mode: BBQ + greenhouse)

Built for the **Wemos D1 mini32 (ESP32-WROOM, 4 MB flash)**, Arduino-ESP32 core 2.0.17,
default partition table. The web page (`data/`) is included in `spiffs.bin`.

## Update (keeps your settings: wifi, targets, calibration)

```
esptool.py --chip esp32 --baud 921600 write_flash 0x10000 firmware.bin 0x290000 spiffs.bin
```

## Clean install (new board, or when something is badly broken)

Erases everything, including the saved settings:

```
esptool.py --chip esp32 --baud 921600 write_flash 0x0 diy-app-engine-full-flash.bin
```

or, the same with the separate files:

```
esptool.py --chip esp32 --baud 921600 write_flash 0x1000 bootloader.bin 0x8000 partitions.bin 0xe000 boot_app0.bin 0x10000 firmware.bin 0x290000 spiffs.bin
```

No Python? Use the browser flasher https://espressif.github.io/esptool-js/ (Chrome/Edge,
USB cable): add the files with the addresses above and press *Program*.

## Over wifi from the greenhouse firmware (no cable)

The partition table is the same as the single-mode firmwares, so a greenhouse controller can be
moved to this firmware over wifi: open `http://<controller-ip>/update`, upload `firmware.bin` as
*Firmware*, and right after the restart upload `spiffs.bin` as *Filesystem* (until then the page
is missing, `/update` keeps working). The saved settings are kept and the controller starts in
greenhouse mode. The single-mode BBQ firmware has no updater, so a BBQ controller needs the USB
cable once (use the *Update* command above to keep its settings); after that `/update` works in
both modes.

# PET2001 for [MiSTer Board](https://github.com/MiSTer-devel/Main_MiSTer/wiki)

### This is the port of [pet2001fpga](https://github.com/skibo/Pet2001_Nexys3).

### Ported to MiST and DeMiSTified platforms by Alastair M. Robinson

## ROM format
Suitable ROMs can be found in the VICE emulator package and should be concatenated into
a single file called PET2001.ROM
The ROM chunks should appear in the following order:
* BASIC ROM (12k)
* Edit ROM (2k)
* Characters ROM (2k)
* Kernal ROM (4k)
The ROM file should be 20k in total.


## Installation:
Copy the *.rbf file at the root of the SD card. Copy roms (*.prg,*.tap) to **PET2001** folder.

### Notes:
* PRG apps are directly injected into RAM. Load command is not required.
* TAP files are loaded through virtual tape input. press **F1** to issue LOAD command, and then choose TAP file in OSD.
* **F12** opens OSD.

## Download precompiled binaries
Go to [releases](https://github.com/MiSTer-devel/PET2001_MiSTer/tree/master/releases) folder.

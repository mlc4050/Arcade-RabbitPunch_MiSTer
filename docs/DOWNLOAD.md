# ROM image download control

rabbitpunch_download accepts a sequential 16-bit raw image stream using
valid/ready and byte addresses 0, 2, ... ROM_IMAGE_SIZE-2. Data lanes match the
ROM subsystem: low byte is the even byte address. This module has no game-reset
input. Cold FPGA state starts with no valid image and gameplay held in reset.

A download immediately holds game reset. Existing gameplay ROM traffic must
finish before loading mode is asserted. Each accepted stream word is latched,
issued only when the loader is ready, and counted only after its write reply.
Ending the stream waits for the accepted word and transport drain. Exactly
ROM_IMAGE_SIZE bytes are required before image validity and reset release.
Short or nonsequential/odd-address streams invalidate the image, drain safely
and retain reset. A new complete download clears the error and can recover.
The loader remains active through download and CPU reset; do not reset it using
the composite gameplay reset.

The caller must obey valid/ready, quiesce CPU/video requests during download,
and demultiplex image data from DIPs/control indices. This is not an HPS ioctl
implementation or DDR staging engine. No DDR bus is connected yet. A future
ioctl/DDR frontend will provide this stream; soft resets must not start copies.

run_download_tests.py checks delayed/backpressured responses, changed pins after
acceptance, safe entry/final drain, exact acknowledged length, replacement,
short/odd-address rejection and error recovery. A second test writes two distinct
16-byte images through rabbitpunch_roms and the SDRAM command model, then checks
all eight CPU words per image with caches warm across replacement. These small
images exercise ownership and lane contracts; they are not a measured full-ROM
transfer or electrical timing proof. reference/download_checks.json pins both.

The isolated download implementation target uses the full production image size,
same-clock registered test boundaries and the 48 MHz evaluation constraint.
Implementation passes all timing corners with zero block RAM.
reference/download_synth.json records the exact fit and synthetic tester
constraints; it is not a final external-pin or HPS transfer proof.

export BASEDIR?=redox_bootloader

BUILD=build/$(BASEDIR)

TARGET=x86_64-efi-pe

PREFIX=$(CURDIR)/prefix
export LD=$(PREFIX)/bin/$(TARGET)-ld
export RUST_TARGET_PATH=$(CURDIR)/targets
export XARGO_HOME=$(CURDIR)/build/xargo

CARGO=xargo
CARGOFLAGS=--target $(TARGET) --release -- -C soft-float

all: $(BUILD)/boot.img

clean:
	$(CARGO) clean
	rm -rf build

update:
	git submodule update --init --recursive --remote
	cargo update

qemu: $(BUILD)/boot.img
	kvm -m 1024 -serial mon:stdio -net none -vga std -bios /usr/share/ovmf/OVMF.fd $<

$(BUILD)/boot.img: $(BUILD)/efi.img
	dd if=/dev/zero of=$@.tmp bs=512 count=100352
	parted $@.tmp -s -a minimal mklabel gpt
	parted $@.tmp -s -a minimal mkpart EFI FAT16 2048s 93716s
	parted $@.tmp -s -a minimal toggle 1 boot
	dd if=$< of=$@.tmp bs=512 count=98304 seek=2048 conv=notrunc
	mv $@.tmp $@

$(BUILD)/efi.img: $(BUILD)/boot.efi res/*
	dd if=/dev/zero of=$@.tmp bs=512 count=98304
	mkfs.vfat $@.tmp
	mmd -i $@.tmp efi
	mmd -i $@.tmp efi/boot
	mcopy -i $@.tmp $< ::efi/boot/bootx64.efi
	mmd -i $@.tmp $(BASEDIR)
	mcopy -i $@.tmp -s res ::$(BASEDIR)
	mv $@.tmp $@

$(BUILD)/boot.efi: $(BUILD)/boot.o $(LD)
	$(LD) \
		--oformat pei-x86-64 \
		--dll \
		--image-base 0 \
		--section-alignment 32 \
		--file-alignment 32 \
		--major-os-version 0 \
		--minor-os-version 0 \
		--major-image-version 0 \
		--minor-image-version 0 \
		--major-subsystem-version 0 \
		--minor-subsystem-version 0 \
		--subsystem 10 \
		--heap 0,0 \
		--stack 0,0 \
		--pic-executable \
		--entry _start \
		--no-insert-timestamp \
		$< -o $@

$(BUILD)/boot.o: $(BUILD)/boot.a
	rm -rf $(BUILD)/boot
	mkdir $(BUILD)/boot
	cd $(BUILD)/boot && ar x ../boot.a
	ld -r $(BUILD)/boot/*.o -o $@

$(BUILD)/boot.a: Cargo.lock Cargo.toml src/* src/*/*
	mkdir -p $(BUILD)
	$(CARGO) rustc --lib $(CARGOFLAGS) -C lto --emit link=$@

BINUTILS=2.28.1

prefix/binutils-$(BINUTILS).tar.xz:
	mkdir -p "`dirname $@`"
	wget "https://ftp.gnu.org/gnu/binutils/binutils-$(BINUTILS).tar.xz" -O "$@.partial"
	sha384sum -c binutils.sha384
	mv "$@.partial" "$@"

prefix/binutils-$(BINUTILS): prefix/binutils-$(BINUTILS).tar.xz
	mkdir -p "$@.partial"
	tar --extract --verbose --file "$<" --directory "$@.partial" --strip-components=1
	mv "$@.partial" "$@"

$(LD): prefix/binutils-$(BINUTILS)
	rm -rf prefix/bin prefix/share "prefix/$(TARGET)"
	mkdir -p prefix/build
	cd prefix/build && \
	../../$</configure --target="$(TARGET)" --disable-werror --prefix="$(PREFIX)" && \
	make all-ld -j `nproc` && \
	make install-ld -j `nproc`

# Any copyright is dedicated to the Public Domain.
# http://creativecommons.org/publicdomain/zero/1.0/
# Written by Nils Maier

# This make file will:
#  - Download a set of dependencies and verify the known-good hashes.
#  - Build static libraries of aria2 dependencies.
#  - Create a statically linked, aria2 release.
#    - The build will have all major features enabled, and will use
#      OpenSSL and GMP.
#  - Create a corresponding .tar.bz containing the binaries:
#  - Create a corresponding .pkg installer.
#  - Create a corresponding .dmg image containing said installer.
#
# This Makefile will also run all `make check` targets.
#
# The dependencies currently build are:
#  - zlib (compression, in particular web compression)
#  - openssl
#  - libuv
#  - c-ares (asynchronous DNS resolver)
#  - libxml2 (XML parser, for metalinks)
#  - gmp (multi-precision arithmetric library, for DHKeyExchange, BitTorrent)
#  - sqlite3 (self-contained SQL database, for Firefox3 cookie reading)
#  - cppunit (unit tests for C++, framework in use by aria2 `make check`)
#
#
# To use this Makefile, do something along the lines of
#  - $ mkdir build-release
#  - $ cd build-release
#  - $ virtualenv .
#  - $ . bin/activate
#  - $ pip install sphinx-build
#  - $ ln -s ../makerelease-os.mk Makefile
#  - $ make
#
# If you haven't checkout out a release tag, you need to specify NON_RELEASE.
# $ export NON_RELEASE=1
# to generate a dist with git commit
# $ export NON_RELEASE=force
# to force this script to behave like it was on a tag.
#
# Note: This Makefile expects to be called from a git clone of aria2.
#
# Note: In theory, everything can be build in parallel, however the sub-makes
# will be called with an appropriate -j flag. Building the `deps` target in
# parallel before a general make might be beneficial, as the dependencies
# usually bottle-neck on the configure steps.
#
# Note: Of course, you need to have XCode with the command line tools
# installed for this to work, aka. a working compiler...
#
# Note: We're locally building the dependencies here, static libraries only.
# This is required, because when using brew or MacPorts, which also provide
# dynamic libraries, the linker will pick up the dynamic versions, always,
# with no way to instruct the linker otherwise.
# If you're building aria2 just for yourself and your system, using brewed
# libraries is fine as well.
#
# Note: This Makefile is riddled with mac-isms. It will not work on *nix.
#
# Note: The convoluted way to create separate arch builds and later merge them
# with lipo is because of two things:
#  1) Avoid patching c-ares, which hardcodes some sizes in its headers.
#
# Note: This Makefile uses resources from osx-package when creating the
# *.pkg and *.dmg targets

SHELL := bash

# A bit awkward, but OSX doesn't have a proper `readlink -f`.
SRCDIR := $(shell dirname $(lastword $(shell stat -f "%N %Y" $(lastword $(MAKEFILE_LIST)))))

# Same as in script-helper, but a bit easier on the eye (but more error prone)
# and Makefile compatible
BASE_VERSION = def
VERSION := $(BASE_VERSION)

# Set up compiler.
ARCH = x86_64
CC = clang
export CC
CXX = clang++
export CXX

# Set up compiler/linker flags.
PLATFORMFLAGS ?= -mmacosx-version-min=10.12
OPTFLAGS ?= -Os
CFLAGS ?= $(PLATFORMFLAGS) $(OPTFLAGS)
export CFLAGS
CXXFLAGS ?= $(PLATFORMFLAGS) $(OPTFLAGS)
export CXXFLAGS
LDFLAGS ?= -Wl,-dead_strip
export LDFLAGS

LTO_FLAGS = -flto -ffunction-sections -fdata-sections

# Dependency versions
zlib_version = 1.3.2
zlib_hash = bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16
zlib_url = https://zlib.net/fossils/zlib-$(zlib_version).tar.gz


openssl_version = 1.1.1w
openssl_hash = cf3098950cb4d853ad95c0841f1f9c6d3dc102dccfcacd521d93925208b76ac8
openssl_url = https://github.com/openssl/openssl/releases/download/OpenSSL_1_1_1w/openssl-1.1.1w.tar.gz

libxml2_version = 2.15.3
libxml2_hash = 78262a6e7ac170d6528ebfe2efccdf220191a5af6a6cd61ea4a9a9a5042c7a07
libxml2_url = https://download.gnome.org/sources/libxml2/2.15/libxml2-$(libxml2_version).tar.xz
libxml2_cflags=$(CFLAGS) $(LTO_FLAGS)
libxml2_ldflags=$(CFLAGS) $(LTO_FLAGS)
libxml2_nocheck = yes

cares_version = 1.34.8
cares_hash = c222b6d681096f9444d2c4863d2c1174019e27cacca0a4a5c114d36dd7d7bf78
cares_url = https://github.com/c-ares/c-ares/releases/download/v$(cares_version)/c-ares-$(cares_version).tar.gz
cares_confflags = "--enable-optimize=$(OPTFLAGS)"
cares_cflags=$(CFLAGS) $(LTO_FLAGS)
cares_ldflags=$(CFLAGS) $(LTO_FLAGS)

sqlite_version = autoconf-3460100
sqlite_hash = 67d3fe6d268e6eaddcae3727fce58fcc8e9c53869bdd07a0c61e38ddf2965071
sqlite_url = https://sqlite.org/2024/sqlite-$(sqlite_version).tar.gz
sqlite_cflags=$(CFLAGS) $(LTO_FLAGS)
sqlite_ldflags=$(CFLAGS) $(LTO_FLAGS) -framework Security -framework Foundation

gmp_version = 6.3.0
gmp_hash = ac28211a7cfb609bae2e2c8d6058d66c8fe96434f740cf6fe2e47b000d1c20cb
gmp_url = https://ftp.gnu.org/gnu/gmp/gmp-$(gmp_version).tar.bz2
gmp_confflags = --disable-cxx --enable-assembly --with-pic --enable-fat
gmp_cflags=$(CFLAGS)
gmp_cxxflags=$(CXXFLAGS)

libuv_version = v1.52.1
libuv_hash = 66d511b9e6e334c0e62279eb234fbfb2b3110b1479c09b95b44c7afca8cff9e7
libuv_url = https://dist.libuv.org/dist/$(libuv_version)/libuv-$(libuv_version).tar.gz
libuv_confflags = --disable-silent-rules

libssh2_version = 1.11.1
libssh2_hash = 9954cb54c4f548198a7cbebad248bdc87dd64bd26185708a294b2b50771e3769
libssh2_url = https://www.libssh2.org/download/libssh2-$(libssh2_version).tar.xz
libssh2_cflags=$(CFLAGS) $(LTO_FLAGS)
libssh2_cxxflags=$(CXXFLAGS) $(LTO_FLAGS)
libssh2_ldflags=$(CFLAGS) $(LTO_FLAGS)
libssh2_confflags = --with-pic
libssh2_nocheck = yes


# ARCHLIBS that can be template build
ARCHLIBS = libxml2 cares sqlite gmp libssh2
# NONARCHLIBS that cannot be template build
NONARCHLIBS = libuv zlib openssl


# Aria2 setup
ARIA2 := aria2-$(VERSION)
ARIA2_PREFIX := $(PWD)/$(ARIA2)
ARIA2_CONFFLAGS = \
		--without-appletls \
		--without-gnutls \
		--without-python \
		--with-openssl \
		--with-libuv \
		--with-libssh2 \
		--with-sqlite3 \
		--disable-libaria2 \
		ARIA2_STATIC=yes \
		--enable-shared=no



## --without-python ：libxml2不使用Python就不会被本机 Miniconda 环境影响
## --with-ca-bundle='/etc/ssl/cert.pem' ：指定证书路径，可以不用指定因为LibsslTLSContext.cc中有多个可选证书路径，根据路径查找
## 原始的指定证书的方式
# ARIA2_CONFFLAGS = \
# 		--without-appletls \
# 		--without-gnutls \
# 		--with-openssl \
# 		--with-libuv \
# 		--with-libssh2 \
# 		--with-sqlite3 \
# 		--with-ca-bundle='/usr/local/etc/openssl/cert.pem' \
# 		--disable-libaria2 \
# 		ARIA2_STATIC=yes \
# 		--enable-shared=no







# Detect number of CPUs to be used with make -j
CPUS = $(shell sysctl hw.ncpu | cut -d" " -f2)

# default target
all::

# All those .PRECIOUS files, because otherwise gmake will treat them as
# intermediates and remove them when the build completes. Thanks gmake!
.PRECIOUS: %.tar.gz
%.tar.gz:
	curl -o $@ -A 'curl/0; like wget' -L \
		$($(basename $(basename $@))_url)

.PRECIOUS: %.check
%.check: %.tar.gz
	@if test "$$(shasum -a256 $< | awk '{print $$1}')" != "$($(basename $@)_hash)"; then \
		echo "Invalid $@ hash"; \
		rm -f $<; \
		exit 1; \
	fi;
	touch $@

.PRECIOUS: %.stamp
%.stamp: %.tar.gz %.check
	tar xf $<
	mv $(basename $@)-$($(basename $@)_version) $(basename $@)
	touch $@

.PRECIOUS: cares.stamp
cares.stamp: cares.tar.gz cares.check
	tar xf $<
	mv c-ares-$($(basename $@)_version) $(basename $@)
	touch $@

# Using (NON)ARCH_template kinda stinks, but real multi-target pattern rules
# only exist in feverish dreams.
define NONARCH_template
$(1).build: $(1).$(ARCH).build

deps:: $(1).build

endef

.PRECIOUS: zlib.%.build
zlib.%.build: zlib.stamp
	$(eval BASE := $(basename $<))
	$(eval DEST := $(basename $@))
	$(eval ARCH := $(subst .,,$(suffix $(DEST))))
	rsync -a $(BASE)/ $(DEST)
	( cd $(DEST) && ./configure \
		--static --prefix=$(PWD)/arch \
		)
	$(MAKE) -C $(DEST) -sj$(CPUS) CFLAGS="$(CFLAGS) $(LTO_FLAGS) -arch $(ARCH)"
	$(MAKE) -C $(DEST) -sj$(CPUS) CFLAGS="$(CFLAGS) $(LTO_FLAGS) -arch $(ARCH)" check
	$(MAKE) -C $(DEST) -s install
	touch $@

.PRECIOUS: openssl.%.build
openssl.%.build: openssl.stamp
	$(eval BASE := $(basename $<))
	$(eval DEST := $(basename $@))
	$(eval ARCH := $(subst .,,$(suffix $(DEST))))
	rsync -a $(BASE)/ $(DEST)
	( cd $(DEST) && ./config \
		--static zlib --prefix=$(PWD)/arch no-weak-ssl-ciphers -Wa,--noexecstack\
		)
	$(MAKE) -C $(DEST) -sj$(CPUS) CFLAGS="$(CFLAGS) $(LTO_FLAGS) -arch $(ARCH)"
	$(MAKE) -C $(DEST) -s install
	touch $@

.PRECIOUS: libuv.%.build
libuv.%.build: libuv.stamp
	$(eval BASE := $(basename $<))
	$(eval DEST := $(basename $@))
	$(eval ARCH := $(subst .,,$(suffix $(DEST))))
	rsync -a $(BASE)/ $(DEST)
	( cd $(DEST) && ./autogen.sh && ./configure \
		--enable-static --disable-shared --prefix=$(PWD)/arch \
		)
	$(MAKE) -C $(DEST) -sj$(CPUS) CFLAGS="$(CFLAGS) $(LTO_FLAGS) -arch $(ARCH)"
	$(MAKE) -C $(DEST) -s install
	touch $@

$(foreach lib,$(NONARCHLIBS),$(eval $(call NONARCH_template,$(lib))))

define ARCH_template
.PRECIOUS: $(1).%.build
$(1).%.build: $(1).stamp
	$$(eval DEST := $$(basename $$@))
	$$(eval ARCH := $$(subst .,,$$(suffix $$(DEST))))
	mkdir -p $$(DEST)
	( cd $$(DEST) && ../$(1)/configure \
		--enable-static --disable-shared \
		--prefix=$(PWD)/arch \
		$$($(1)_confflags) \
		CFLAGS="$$($(1)_cflags) -arch $$(ARCH)" \
		CXXFLAGS="$$($(1)_cxxflags) -arch $$(ARCH) -std=c++11" \
		LDFLAGS="$(LDFLAGS) $$($(1)_ldflags)" \
		PKG_CONFIG_PATH=$$(PWD)/arch/lib/pkgconfig \
		)
	$$(MAKE) -C $$(DEST) -sj$(CPUS)
	if test -z '$$($(1)_nocheck)'; then $$(MAKE) -C $$(DEST) -sj$(CPUS) check; fi
	$$(MAKE) -C $$(DEST) -s install
	touch $$@

$(1).build: $(1).$(ARCH).build

deps:: $(1).build

endef

$(foreach lib,$(ARCHLIBS),$(eval $(call ARCH_template,$(lib))))

.PRECIOUS: aria2.%.build
aria2.%.build: libuv.%.build zlib.%.build openssl.%.build libxml2.%.build gmp.%.build cares.%.build sqlite.%.build libssh2.%.build
	$(eval DEST := $$(basename $$@))
	$(eval ARCH := $$(subst .,,$$(suffix $$(DEST))))
	mkdir -p $(DEST)
	rsync -a $(SRCDIR)/../aria2/ $(DEST)
	find $(PWD)/arch/lib -name "*.dylib" -delete
	( cd $(DEST) && autoreconf -i && ./configure \
		--prefix=$(ARIA2_PREFIX) \
		--bindir=$(PWD)/$(DEST) \
		--sysconfdir=/usr/local/etc \
		$(ARIA2_CONFFLAGS) \
		CFLAGS="$(CFLAGS) $(LTO_FLAGS) -arch $(ARCH) -I$(PWD)/arch/include" \
		CXXFLAGS="$(CXXFLAGS) $(LTO_FLAGS) -arch $(ARCH) -I$(PWD)/arch/include" \
		LDFLAGS="$(LDFLAGS) $(CXXFLAGS) $(LTO_FLAGS) -L$(PWD)/arch/lib" \
		PKG_CONFIG_PATH=$(PWD)/arch/lib/pkgconfig \
		)
	$(MAKE) -C $(DEST) -sj$(CPUS)
	# $(MAKE) -C $(DEST) -sj$(CPUS) check
	# Check that the resulting executable is Position-independent (PIE)
	otool -hv $(DEST)/src/aria2c | grep -q PIE
	$(MAKE) -C $(DEST) -sj$(CPUS) install-strip
	touch $@

aria2.build: aria2.$(ARCH).build
	mkdir -p $(ARIA2_PREFIX)/bin
	cp -f aria2.$(ARCH)/aria2c $(ARIA2_PREFIX)/bin/aria2c
	arch -64 $(ARIA2_PREFIX)/bin/aria2c -v
	touch $@

all:: aria2.build

clean:
	rm -rf *aria2*

.PHONY: all multi clean
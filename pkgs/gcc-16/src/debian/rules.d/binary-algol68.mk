ifneq ($(DEB_STAGE),rtlibs)
  ifeq (0,1)
  ifneq (,$(filter yes, $(biarch64) $(biarch32) $(biarchn32) $(biarchx32)))
    arch_binaries  := $(arch_binaries) ga68-multi
  endif
  endif
  arch_binaries := $(arch_binaries) ga68-nat ga68-host
  ifeq ($(unprefixed_names),yes)
    arch_binaries := $(arch_binaries) ga68
    indep_binaries := $(indep_binaries) ga68-build
  endif

  ifeq ($(with_algoldev),yes)
    $(lib_binaries) += libga68-dev
  endif
  ifeq ($(with_libga68),yes)
    $(lib_binaries) += libga68
  endif

  ifneq ($(DEB_CROSS),yes)
    indep_binaries := $(indep_binaries) ga68-doc
  endif

  ifeq (0,1)
  ifeq ($(with_lib64ga68dev),yes)
    $(lib_binaries)	+= lib64ga68-dev
  endif
  ifeq ($(with_lib32ga68dev),yes)
    $(lib_binaries)	+= lib32ga68-dev
  endif
  ifeq ($(with_libn32ga68dev),yes)
    $(lib_binaries)	+= libn32ga68-dev
  endif
  ifeq ($(with_libx32ga68dev),yes)
    $(lib_binaries)	+= libx32ga68-dev
  endif

  ifeq ($(with_lib64ga68),yes)
    $(lib_binaries)	+= lib64ga68
  endif
  ifeq ($(with_lib32ga68),yes)
    $(lib_binaries)	+= lib32ga68
  endif
  ifeq ($(with_libn32ga68),yes)
    $(lib_binaries)	+= libn32ga68
  endif
  ifeq ($(with_libx32ga68),yes)
    $(lib_binaries)	+= libx32ga68
  endif
  endif
endif

p_ga68_n	= ga68$(pkg_ver)-$(subst _,-,$(TARGET_ALIAS))
p_ga68_h	= ga68$(pkg_ver)-for-host
p_ga68_b	= ga68$(pkg_ver)-for-build
p_ga68	= ga68$(pkg_ver)
p_ga68_m	= ga68$(pkg_ver)-multilib$(cross_bin_arch)
p_libga68	= libga68-$(GA68_SONAME)
p_libga68dev	= libga68$(pkg_ver)-dev
p_ga68d	= ga68$(pkg_ver)-doc

d_ga68_n	= debian/$(p_ga68_n)
d_ga68_h	= debian/$(p_ga68_h)
d_ga68_b	= debian/$(p_ga68_b)
d_ga68	= debian/$(p_ga68)
d_ga68_m	= debian/$(p_ga68_m)
d_libga68	= debian/$(p_libga68)
d_libga68dev	= debian/$(p_libga68dev)
d_ga68d	= debian/$(p_ga68d)

dirs_ga68_n = \
	$(PF)/bin \
	$(PF)/share/man/man1 \
	$(gcc_lexec_dir) \
	$(gcc_lib_dir) \
	usr/share/lintian/overrides
#ifneq ($(DEB_CROSS),yes)
#  dirs_ga68_n += \
#	$(ga68_include_dir)
#endif

dirs_ga68 = \
	$(PF)/bin \
	$(PF)/share/man/man1 \
	$(docdir)/$(p_xbase)/Algol68

files_ga68_n = \
	$(PF)/bin/$(cmd_prefix)ga68$(pkg_ver) \
	$(PF)/share/man/man1/$(cmd_prefix)ga68$(pkg_ver).1 \
	$(gcc_lexec_dir)/a681

dirs_libga68 = \
	$(PF)/lib \
	$(ga68_include_dir) \
	$(gcc_lib_dir)

$(binary_stamp)-ga68-nat: $(install_stamp)
	dh_testdir
	dh_testroot
	mv $(install_stamp) $(install_stamp)-tmp

	rm -rf $(d_ga68_n)
	dh_installdirs -p$(p_ga68_n) $(dirs_ga68_n)

	$(dh_compat2) dh_movefiles -p$(p_ga68_n) $(files_ga68_n)

	mv $(d)/$(usr_lib)/libga68.spec $(d_ga68_n)/$(gcc_lib_dir)/

ifeq (,$(findstring nostrip,$(DEB_BUILD_OPTONS)))
	$(DWZ) \
	  $(d_ga68_n)/$(gcc_lexec_dir)/a681
endif
	dh_strip -p$(p_ga68_n) \
	  $(if $(unstripped_exe),-X/a681 -X/ga68)
	dh_shlibdeps -p$(p_ga68_n)

	mkdir -p $(d_ga68_n)/usr/share/lintian/overrides
	echo '$(p_ga68_n) binary: hardening-no-pie' \
	  > $(d_ga68_n)/usr/share/lintian/overrides/$(p_ga68_n)

	debian/dh_doclink -p$(p_ga68_n) $(p_xbase)

	echo $(p_ga68_n) >> debian/arch_binaries

	find $(d_ga68_n) -type d -empty -delete

	trap '' 1 2 3 15; touch $@; mv $(install_stamp)-tmp $(install_stamp)

$(binary_stamp)-ga68-host: $(install_stamp)
	dh_testdir
	dh_testroot
	mv $(install_stamp) $(install_stamp)-tmp
	rm -rf $(d_ga68_h)
	debian/dh_doclink -p$(p_ga68_h) $(p_xbase)
	echo $(p_ga68_h) >> debian/arch_binaries
	trap '' 1 2 3 15; touch $@; mv $(install_stamp)-tmp $(install_stamp)

$(binary_stamp)-ga68-build: $(install_stamp)
	dh_testdir
	dh_testroot
	mv $(install_stamp) $(install_stamp)-tmp
	rm -rf $(d_ga68_b)
	debian/dh_doclink -p$(p_ga68_b) $(p_cpp_b)
	echo $(p_ga68_b) >> debian/indep_binaries
	trap '' 1 2 3 15; touch $@; mv $(install_stamp)-tmp $(install_stamp)

$(binary_stamp)-ga68: $(install_stamp)
	dh_testdir
	dh_testroot
	mv $(install_stamp) $(install_stamp)-tmp

	rm -rf $(d_ga68)
	dh_installdirs -p$(p_ga68) $(dirs_ga68)

	cp -p $(srcdir)/gcc/algol68/ChangeLog \
            $(d_ga68)/$(docdir)/$(p_xbase)/Algol68/changelog.algol68
	cp -p $(srcdir)/libga68/ChangeLog \
            $(d_ga68)/$(docdir)/$(p_xbase)/Algol68/changelog.libga68

	debian/dh_doclink -p$(p_ga68) $(p_xbase)

	ln -sf $(cmd_prefix)ga68$(pkg_ver) \
	    $(d_ga68)/$(PF)/bin/ga68$(pkg_ver)
	ln -sf $(cmd_prefix)ga68$(pkg_ver).1.gz \
	    $(d_ga68)/$(PF)/share/man/man1/ga68$(pkg_ver).1.gz
	debian/dh_rmemptydirs -p$(p_ga68)

	echo $(p_ga68) >> debian/arch_binaries
	trap '' 1 2 3 15; touch $@; mv $(install_stamp)-tmp $(install_stamp)

$(binary_stamp)-ga68-multi: $(install_stamp)
	dh_testdir
	dh_testroot
	mv $(install_stamp) $(install_stamp)-tmp

	rm -rf $(d_ga68_m)
	dh_installdirs -p$(p_ga68_m) $(docdir)

	debian/dh_doclink -p$(p_ga68_m) $(p_xbase)

	dh_strip -p$(p_ga68_m)
	dh_shlibdeps -p$(p_ga68_m)
	echo $(p_ga68_m) >> debian/arch_binaries

	trap '' 1 2 3 15; touch $@; mv $(install_stamp)-tmp $(install_stamp)

define __do_libga68
	dh_testdir
	dh_testroot
	mv $(install_stamp) $(install_stamp)-tmp

	rm -rf $(d_l) $(d_d)
	dh_installdirs -p$(p_l) \
		$(usr_lib$(2))
	$(dh_compat2) dh_movefiles -p$(p_l) \
		$(usr_lib$(2))/libga68.so.*

	debian/dh_doclink -p$(p_l) $(p_lbase)
	$(if $(with_dbg),debian/dh_doclink -p$(p_d) $(p_lbase))

	$(call do_strip_lib_dbg, $(p_l), $(p_d), $(v_dbg),,)
	ln -sf libga68.symbols debian/$(p_l).symbols
	$(cross_makeshlibs) dh_makeshlibs $(ldconfig_arg) -p$(p_l) \
		-- -a$(call mlib_to_arch,$(2)) || echo XXXXXXXXXXX ERROR $(p_l)
	rm -f debian/$(p_l).symbols
	$(call cross_mangle_shlibs,$(p_l))
	$(ignshld)DIRNAME=$(subst n,,$(2)) $(cross_shlibdeps) dh_shlibdeps -p$(p_l) \
		$(call shlibdirs_to_search, \
			$(subst ga68$(GA68_SONAME),gcc-s$(GCC_SONAME),$(p_l)) \
			$(subst ga68$(GA68_SONAME),stdc++$(GXX_SONAME),$(p_l)) \
		,$(2)) \
		$(if $(filter yes, $(with_common_libs)),,-- -Ldebian/shlibs.common$(2))
	$(call cross_mangle_substvars,$(p_l))

	mkdir -p $(d_l)/usr/share/lintian/overrides; \
	( \
	  echo "$(p_l) binary: dev-pkg-without-shlib-symlink"; \
	) >> $(d_l)/usr/share/lintian/overrides/$(p_l)

	dh_lintian -p$(p_l)
	echo $(p_l) $(if $(with_dbg), $(p_d)) >> debian/$(lib_binaries)

	trap '' 1 2 3 15; touch $@; mv $(install_stamp)-tmp $(install_stamp)
endef

# install_ga68_lib(lib,soname,flavour,package)
define install_ga68_lib
	dh_link -p$(4) \
	  /$(usr_lib$(3))/$(1).so.$(2) /$(gcc_lib_dir$(3))/$(5)/$(1).so
	rm -f $(d)/$(usr_lib$(3))/$(1).so
	mv $(d)/$(usr_lib$(3))/$(1).a debian/$(4)/$(gcc_lib_dir$(3))/$(5)/$(1).a
endef

define __do_libga68_dev
	dh_testdir
	dh_testroot
	mv $(install_stamp) $(install_stamp)-tmp

	rm -rf $(d_l)
	dh_installdirs -p$(p_l) \
		$(gcc_lib_dir$(2))

	: # install_ga68_lib calls needed?
	$(call install_ga68_lib,libga68,$(GA68_SONAME),$(2),$(p_l))

	debian/dh_doclink -p$(p_l) $(p_lbase)
	echo $(p_l) >> debian/$(lib_binaries)

	trap '' 1 2 3 15; touch $@; mv $(install_stamp)-tmp $(install_stamp)
endef

do_libga68 = $(call __do_libga68,lib$(1)ga68-$(GA68_SONAME),$(1))
do_libga68_dev = $(call __do_libga68_dev,lib$(1)ga68-$(BASE_VERSION)-dev,$(1))

# ----------------------------------------------------------------------
$(binary_stamp)-ga68-doc: $(build_html_stamp) $(install_stamp)
	dh_testdir
	dh_testroot
	mv $(install_stamp) $(install_stamp)-tmp

	rm -rf $(d_ga68d)
	dh_installdirs -p$(p_ga68d) \
		$(docdir)/$(p_xbase)/Algol68 \
		$(PF)/share/info
	cp -p $(d)/$(PF)/share/info/ga68.info \
		$(d_ga68d)/$(PF)/share/info/ga68-$(BASE_VERSION).info
	cp -p $(d)/$(PF)/share/info/ga68-internals.info \
		$(d_ga68d)/$(PF)/share/info/ga68-internals-$(BASE_VERSION).info
	cp -p html/ga68.html $(d_ga68d)/$(docdir)/$(p_xbase)/Algol68/ga68-$(BASE_VERSION).html

	debian/dh_doclink -p$(p_ga68d) $(p_xbase)
	dh_installdocs -p$(p_ga68d)
	rm -f $(d_ga68d)/$(docdir)/$(p_xbase)/copyright

	echo $(p_ga68d) >> debian/indep_binaries

	trap '' 1 2 3 15; touch $@; mv $(install_stamp)-tmp $(install_stamp)


$(binary_stamp)-libga68: $(install_stamp)
	$(call do_libga68,)

$(binary_stamp)-lib64ga68: $(install_stamp)
	$(call do_libga68,64)

$(binary_stamp)-lib32ga68: $(install_stamp)
	$(call do_libga68,32)

$(binary_stamp)-libn32ga68: $(install_stamp)
	$(call do_libga68,n32)

$(binary_stamp)-libx32ga68: $(install_stamp)
	$(call do_libga68,x32)


$(binary_stamp)-libga68-dev: $(install_stamp)
	$(call do_libga68_dev,)

$(binary_stamp)-lib64ga68-dev: $(install_stamp)
	$(call do_libga68_dev,64)

$(binary_stamp)-lib32ga68-dev: $(install_stamp)
	$(call do_libga68_dev,32)

$(binary_stamp)-libx32ga68-dev: $(install_stamp)
	$(call do_libga68_dev,x32)

$(binary_stamp)-libn32ga68-dev: $(install_stamp)
	$(call do_libga68_dev,n32)

ifneq ($(DEB_STAGE),rtlibs)
  ifeq (0,1)
  ifneq (,$(filter yes, $(biarch64) $(biarch32) $(biarchn32) $(biarchx32)))
    arch_binaries  := $(arch_binaries) gcobol-multi
  endif
  endif
  arch_binaries := $(arch_binaries) gcobol-nat gcobol-host
  ifeq ($(unprefixed_names),yes)
    arch_binaries := $(arch_binaries) gcobol
    indep_binaries := $(indep_binaries) gcobol-build
  endif

  ifeq ($(with_coboldev),yes)
    $(lib_binaries) += libgcobol-dev
  endif
  ifeq ($(with_libgcobol),yes)
    $(lib_binaries) += libgcobol
  endif

  ifeq (0,1)
  ifneq ($(DEB_CROSS),yes)
    indep_binaries := $(indep_binaries) gcobol-doc
  endif
  endif

  ifeq (0,1)
  ifeq ($(with_lib64gcoboldev),yes)
    $(lib_binaries)	+= lib64gcobol-dev
  endif
  ifeq ($(with_lib32gcoboldev),yes)
    $(lib_binaries)	+= lib32gcobol-dev
  endif
  ifeq ($(with_libn32gcoboldev),yes)
    $(lib_binaries)	+= libn32gcobol-dev
  endif
  ifeq ($(with_libx32gcoboldev),yes)
    $(lib_binaries)	+= libx32gcobol-dev
  endif

  ifeq ($(with_lib64gcobol),yes)
    $(lib_binaries)	+= lib64gcobol
  endif
  ifeq ($(with_lib32gcobol),yes)
    $(lib_binaries)	+= lib32gcobol
  endif
  ifeq ($(with_libn32gcobol),yes)
    $(lib_binaries)	+= libn32gcobol
  endif
  ifeq ($(with_libx32gcobol),yes)
    $(lib_binaries)	+= libx32gcobol
  endif
  endif
endif

p_gcobol_n	= gcobol$(pkg_ver)-$(subst _,-,$(TARGET_ALIAS))
p_gcobol_h	= gcobol$(pkg_ver)-for-host
p_gcobol_b	= gcobol$(pkg_ver)-for-build
p_gcobol	= gcobol$(pkg_ver)
p_gcobol_m	= gcobol$(pkg_ver)-multilib$(cross_bin_arch)
p_libgcobol	= libgcobol$(GCOBOL_SONAME)
p_libgcoboldev	= libgcobol$(pkg_ver)-dev
p_gcobold	= gcobol$(pkg_ver)-doc

d_gcobol_n	= debian/$(p_gcobol_n)
d_gcobol_h	= debian/$(p_gcobol_h)
d_gcobol_b	= debian/$(p_gcobol_b)
d_gcobol	= debian/$(p_gcobol)
d_gcobol_m	= debian/$(p_gcobol_m)
d_libgcobol	= debian/$(p_libgcobol)
d_libgcoboldev	= debian/$(p_libgcoboldev)
d_gcobold	= debian/$(p_gcobold)

dirs_gcobol_n = \
	$(PF)/bin \
	$(PF)/share/man/man1 \
	$(gcc_lexec_dir) \
	$(gcc_lib_dir) \
	usr/share/lintian/overrides
#ifneq ($(DEB_CROSS),yes)
#  dirs_gcobol_n += \
#	$(gcobol_include_dir)
#endif

dirs_gcobol = \
	$(PF)/bin \
	$(PF)/share/man/man1 \
	$(docdir)/$(p_xbase)/COBOL

files_gcobol_n = \
	$(PF)/bin/$(cmd_prefix)gcobol$(pkg_ver) \
	$(PF)/bin/$(cmd_prefix)gcobc$(pkg_ver) \
	$(gcc_lexec_dir)/cobol1
ifneq ($(GFDL_INVARIANT_FREE),yes-now-pure-gfdl)
    files_gcobol_n += \
	$(PF)/share/man/man1/$(cmd_prefix)gcobol$(pkg_ver).1
endif

dirs_libgcobol = \
	$(PF)/lib \
	$(gcobol_include_dir) \
	$(gcc_lib_dir)

$(binary_stamp)-gcobol-nat: $(install_stamp)
	dh_testdir
	dh_testroot
	mv $(install_stamp) $(install_stamp)-tmp

	rm -rf $(d_gcobol_n)
	dh_installdirs -p$(p_gcobol_n) $(dirs_gcobol_n)

	$(dh_compat2) dh_movefiles -p$(p_gcobol_n) $(files_gcobol_n)

	mv $(d)/$(usr_lib)/libgcobol.spec $(d_gcobol_n)/$(gcc_lib_dir)/

ifeq (,$(findstring nostrip,$(DEB_BUILD_OPTONS)))
	$(DWZ) \
	  $(d_gcobol_n)/$(gcc_lexec_dir)/cobol1
endif
	dh_strip -p$(p_gcobol_n) \
	  $(if $(unstripped_exe),-X/cobol1 -X/gcobol)
	dh_shlibdeps -p$(p_gcobol_n)

	mkdir -p $(d_gcobol_n)/usr/share/lintian/overrides
	( \
	  echo '$(p_gcobol_n) binary: hardening-no-pie'; \
	  echo '$(p_gcobol_n) binary: no-manual-page'; \
	) > $(d_gcobol_n)/usr/share/lintian/overrides/$(p_gcobol_n)

	debian/dh_doclink -p$(p_gcobol_n) $(p_xbase)

	echo $(p_gcobol_n) >> debian/arch_binaries

	find $(d_gcobol_n) -type d -empty -delete

	trap '' 1 2 3 15; touch $@; mv $(install_stamp)-tmp $(install_stamp)

$(binary_stamp)-gcobol-host: $(install_stamp)
	dh_testdir
	dh_testroot
	mv $(install_stamp) $(install_stamp)-tmp
	rm -rf $(d_gcobol_h)
	debian/dh_doclink -p$(p_gcobol_h) $(p_xbase)
	echo $(p_gcobol_h) >> debian/arch_binaries
	trap '' 1 2 3 15; touch $@; mv $(install_stamp)-tmp $(install_stamp)

$(binary_stamp)-gcobol-build: $(install_stamp)
	dh_testdir
	dh_testroot
	mv $(install_stamp) $(install_stamp)-tmp
	rm -rf $(d_gcobol_b)
	debian/dh_doclink -p$(p_gcobol_b) $(p_cpp_b)
	echo $(p_gcobol_b) >> debian/indep_binaries
	trap '' 1 2 3 15; touch $@; mv $(install_stamp)-tmp $(install_stamp)

$(binary_stamp)-gcobol: $(install_stamp)
	dh_testdir
	dh_testroot
	mv $(install_stamp) $(install_stamp)-tmp

	rm -rf $(d_gcobol)
	dh_installdirs -p$(p_gcobol) $(dirs_gcobol)

#	cp -p $(srcdir)/gcc/cobol/ChangeLog \
#            $(d_gcobol)/$(docdir)/$(p_xbase)/COBOL/changelog.cobol

	ln -sf $(cmd_prefix)gcobc$(pkg_ver) \
	    $(d_gcobol)/$(PF)/bin/gcobc$(pkg_ver)
	ln -sf $(cmd_prefix)gcobol$(pkg_ver) \
	    $(d_gcobol)/$(PF)/bin/gcobol$(pkg_ver)
ifneq ($(GFDL_INVARIANT_FREE),yes-now-pure-gfdl)
	ln -sf $(cmd_prefix)gcobol$(pkg_ver).1.gz \
	    $(d_gcobol)/$(PF)/share/man/man1/gcobol$(pkg_ver).1.gz
endif
	debian/dh_doclink -p$(p_gcobol) $(p_xbase)

	debian/dh_rmemptydirs -p$(p_gcobol)

	echo $(p_gcobol) >> debian/arch_binaries
	trap '' 1 2 3 15; touch $@; mv $(install_stamp)-tmp $(install_stamp)

$(binary_stamp)-gcobol-multi: $(install_stamp)
	dh_testdir
	dh_testroot
	mv $(install_stamp) $(install_stamp)-tmp

	rm -rf $(d_gcobol_m)
	dh_installdirs -p$(p_gcobol_m) $(docdir)

	debian/dh_doclink -p$(p_gcobol_m) $(p_xbase)

	dh_strip -p$(p_gcobol_m)
	dh_shlibdeps -p$(p_gcobol_m)
	echo $(p_gcobol_m) >> debian/arch_binaries

	trap '' 1 2 3 15; touch $@; mv $(install_stamp)-tmp $(install_stamp)

define __do_libgcobol
	dh_testdir
	dh_testroot
	mv $(install_stamp) $(install_stamp)-tmp

	rm -rf $(d_l) $(d_d)
	dh_installdirs -p$(p_l) \
		$(usr_lib$(2))
	$(dh_compat2) dh_movefiles -p$(p_l) \
		$(usr_lib$(2))/libgcobol.so.*

	debian/dh_doclink -p$(p_l) $(p_lbase)
	$(if $(with_dbg),debian/dh_doclink -p$(p_d) $(p_lbase))

	$(call do_strip_lib_dbg, $(p_l), $(p_d), $(v_dbg),,)
	ln -sf libgcobol.symbols debian/$(p_l).symbols
	$(cross_makeshlibs) dh_makeshlibs $(ldconfig_arg) -p$(p_l) \
		-- -a$(call mlib_to_arch,$(2)) || echo XXXXXXXXXXX ERROR $(p_l)
	rm -f debian/$(p_l).symbols
	$(call cross_mangle_shlibs,$(p_l))
	$(ignshld)DIRNAME=$(subst n,,$(2)) $(cross_shlibdeps) dh_shlibdeps -p$(p_l) \
		$(call shlibdirs_to_search, \
			$(subst gcobol$(GCOBOL_SONAME),gcc-s$(GCC_SONAME),$(p_l)) \
			$(subst gcobol$(GCOBOL_SONAME),stdc++$(GXX_SONAME),$(p_l)) \
		,$(2)) \
		$(if $(filter yes, $(with_common_libs)),,-- -Ldebian/shlibs.common$(2))
	$(call cross_mangle_substvars,$(p_l))

	mkdir -p $(d_l)/usr/share/lintian/overrides; \
	( \
	  echo "$(p_l) binary: dev-pkg-without-shlib-symlink"; \
	) >> $(d_l)/usr/share/lintian/overrides/$(p_l)
	$(if $(findstring native, $(build_type)),,
	  echo "$(p_l) binary: embedded-library" \
	  >> $(d_l)/usr/share/lintian/overrides/$(p_l)
	)

	dh_lintian -p$(p_l)
	echo $(p_l) $(if $(with_dbg), $(p_d)) >> debian/$(lib_binaries)

	trap '' 1 2 3 15; touch $@; mv $(install_stamp)-tmp $(install_stamp)
endef

# install_gcobol_lib(lib,soname,flavour,package)
define install_gcobol_lib
	dh_link -p$(4) \
	  /$(usr_lib$(3))/$(1).so.$(2) /$(gcc_lib_dir$(3))/$(5)/$(1).so
	rm -f $(d)/$(usr_lib$(3))/$(1).so
	rm -f $(d)/$(usr_lib$(3))/$(1).a
endef

define __do_libgcobol_dev
	dh_testdir
	dh_testroot
	mv $(install_stamp) $(install_stamp)-tmp

	rm -rf $(d_l)
	dh_installdirs -p$(p_l) \
		$(gcc_lib_dir$(2))

	$(if $(findstring native, $(build_type)),
	$(if $(2),,
	mkdir -p $(d_l)/$(PF)/share/man/man3
	mv $(d)/$(PF)/share/man/man3/$(cmd_prefix)gcobol-io$(pkg_ver).3 \
		$(d_l)/$(PF)/share/man/man3/.
	))
	$(if $(EMPTY),,
	$(if $(2),,
	dh_installdirs -p$(p_l) \
		$(gcc_lib_dir$(2))/cobol
	$(dh_compat2) dh_movefiles -p$(p_l) \
		$(gcc_lib_dir$(2))/cobol/{compat,posix}
	)
	)

	: # install_gcobol_lib calls needed?
	$(call install_gcobol_lib,libgcobol,$(GCOBOL_SONAME),$(2),$(p_l))

	debian/dh_doclink -p$(p_l) $(p_lbase)
	echo $(p_l) >> debian/$(lib_binaries)

	trap '' 1 2 3 15; touch $@; mv $(install_stamp)-tmp $(install_stamp)
endef

do_libgcobol = $(call __do_libgcobol,lib$(1)gcobol$(GCOBOL_SONAME),$(1))
do_libgcobol_dev = $(call __do_libgcobol_dev,lib$(1)gcobol-$(BASE_VERSION)-dev,$(1))

# ----------------------------------------------------------------------
$(binary_stamp)-gcobol-doc: $(build_html_stamp) $(install_stamp)
	dh_testdir
	dh_testroot
	mv $(install_stamp) $(install_stamp)-tmp

	rm -rf $(d_gcobold)
	dh_installdirs -p$(p_gcobold) \
		$(docdir)/$(p_gcobol) \
		$(docdir)/$(p_xbase) \
		$(PF)/share/info
	cp -p $(builddir)/gcc/doc/gcobol.info \
	  $(d_gcobold)/$(PF)/share/info/gcobol-$(BASE_VERSION).info
	cp -p html/gcobol.html \
	  $(d_gcobold)/$(docdir)/$(p_xbase)/cobol/gcobol-$(BASE_VERSION).html
	ln -sf ../$(p_xbase)/cobol/gcobol-$(BASE_VERSION).html \
	  $(d_gcobold)/$(docdir)/$(p_gcobol)/gcobol-$(BASE_VERSION).html

	debian/dh_doclink -p$(p_gcobold) $(p_xbase)
	dh_installdocs -p$(p_gcobold)
	rm -f $(d_gcobold)/$(docdir)/$(p_xbase)/copyright

	echo $(p_gcobold) >> debian/indep_binaries

	trap '' 1 2 3 15; touch $@; mv $(install_stamp)-tmp $(install_stamp)


$(binary_stamp)-libgcobol: $(install_stamp)
	$(call do_libgcobol,)

$(binary_stamp)-lib64gcobol: $(install_stamp)
	$(call do_libgcobol,64)

$(binary_stamp)-lib32gcobol: $(install_stamp)
	$(call do_libgcobol,32)

$(binary_stamp)-libn32gcobol: $(install_stamp)
	$(call do_libgcobol,n32)

$(binary_stamp)-libx32gcobol: $(install_stamp)
	$(call do_libgcobol,x32)


$(binary_stamp)-libgcobol-dev: $(install_stamp)
	$(call do_libgcobol_dev,)

$(binary_stamp)-lib64gcobol-dev: $(install_stamp)
	$(call do_libgcobol_dev,64)

$(binary_stamp)-lib32gcobol-dev: $(install_stamp)
	$(call do_libgcobol_dev,32)

$(binary_stamp)-libx32gcobol-dev: $(install_stamp)
	$(call do_libgcobol_dev,x32)

$(binary_stamp)-libn32gcobol-dev: $(install_stamp)
	$(call do_libgcobol_dev,n32)

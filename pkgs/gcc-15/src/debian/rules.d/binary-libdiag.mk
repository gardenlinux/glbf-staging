ifeq ($(with_libdiag),yes)
  $(lib_binaries)  += libdiag
endif

$(lib_binaries)  += libdiagdev

arch_binaries	:= $(arch_binaries) diag

ifneq ($(DEB_CROSS),yes)
#  indep_binaries := $(indep_binaries) libdiagdoc
endif

p_diag		= gcc$(pkg_ver)-diagnostics
p_diaglib	= libgdiagnostics$(DIAGNOSTICS_SONAME)
p_diagdbg	= libgdiagnostics$(DIAGNOSTICS_SONAME)-dbg
p_diagdev	= libgdiagnostics$(pkg_ver)-dev
p_diagdoc	= libgdiagnostics$(pkg_ver)-doc

d_diag		= debian/$(p_diag)
d_diaglib	= debian/$(p_diaglib)
d_diagdev	= debian/$(p_diagdev)
d_diagdbg	= debian/$(p_diagdbg)
d_diagdoc	= debian/$(p_diagdoc)

$(binary_stamp)-libdiag: $(install_jit_stamp)
	dh_testdir
	dh_testroot
	mv $(install_stamp) $(install_stamp)-tmp

	rm -rf $(d_diaglib) $(d_diagdbg)
	dh_installdirs -p$(p_diaglib) \
		$(usr_lib)
ifeq ($(with_dbg),yes)
	dh_installdirs -p$(p_diagdbg)
endif

	$(dh_compat2) dh_movefiles -p$(p_diaglib) \
		$(usr_lib)/libgdiagnostics.so.*
	rm -f $(d)/$(usr_lib)/libgdiagnostics.so

	debian/dh_doclink -p$(p_diaglib) $(p_base)
ifeq ($(with_dbg),yes)
	debian/dh_doclink -p$(p_diagdbg) $(p_base)
endif

	$(call do_strip_lib_dbg, $(p_diaglib), $(p_diagdbg), $(v_dbg),,)
	$(cross_makeshlibs) dh_makeshlibs -p$(p_diaglib)
	$(call cross_mangle_shlibs,$(p_diaglib))
	$(ignshld)$(cross_shlibdeps) dh_shlibdeps -p$(p_diaglib) \
		$(if $(filter yes, $(with_common_libs)),,-- -Ldebian/shlibs.common$(2))
	$(call cross_mangle_substvars,$(p_diaglib))
	echo $(p_diaglib) $(if $(with_dbg), $(p_diagdbg)) >> debian/arch_binaries

	trap '' 1 2 3 15; touch $@; mv $(install_stamp)-tmp $(install_stamp)
	touch $@

$(binary_stamp)-libdiagdev: $(install_jit_stamp)
	dh_testdir
	dh_testroot
	mv $(install_stamp) $(install_stamp)-tmp

	rm -rf $(d_diagdev)
	dh_installdirs -p$(p_diagdev) \
		$(usr_lib) \
		$(gcc_lib_dir)/include

	rm -f $(d)/$(usr_lib)/libgdiagnostics.so

	$(dh_compat2) dh_movefiles -p$(p_diagdev) \
		$(gcc_lib_dir)/include/libgdiagnostics*.h
	dh_link -p$(p_diagdev) \
		$(usr_lib)/libgdiagnostics.so.$(GCCJIT_SONAME) $(gcc_lib_dir)/libgdiagnostics.so

	debian/dh_doclink -p$(p_diagdev) $(p_base)

	echo $(p_diagdev) >> debian/arch_binaries

	trap '' 1 2 3 15; touch $@; mv $(install_stamp)-tmp $(install_stamp)
	touch $@

$(binary_stamp)-libdiagdoc: $(install_jit_stamp)
	dh_testdir
	dh_testroot
	mv $(install_stamp) $(install_stamp)-tmp

	rm -rf $(d_diagdoc)
	dh_installdirs -p$(p_diagdoc) \
		$(PF)/share/info

	$(dh_compat2) dh_movefiles -p$(p_diagdoc) \
		$(PF)/share/info/libgdiagnostics*

	debian/dh_doclink -p$(p_diagdoc) $(p_base)
	echo $(p_diagdoc) >> debian/indep_binaries

	trap '' 1 2 3 15; touch $@; mv $(install_stamp)-tmp $(install_stamp)
	touch $@

$(binary_stamp)-diag: $(install_jit_stamp) $(binary_stamp)-libdiag
	dh_testdir
	dh_testroot
	mv $(install_stamp) $(install_stamp)-tmp

	rm -rf $(d_diag)
	dh_installdirs -p$(p_diag) \
		$(PF)/bin \
		$(PF)/share/man/man1

	$(dh_compat2) dh_movefiles -p$(p_diag) \
		$(PF)/bin/$(cmd_prefix)sarif-replay$(pkg_ver)
	dh_link -p$(p_diag) \
		$(PF)/bin/$(cmd_prefix)sarif-replay$(pkg_ver) $(PF)/bin/sarif-replay$(pkg_ver)

	if which help2man >/dev/null 2>&1; then \
	  LD_LIBRARY_PATH=$(CURDIR)/$(d_diaglib)/$(usr_lib):/usr/lib/$(DEB_HOST_MULTIARCH)/libfakeroot${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH} \
	    help2man --no-discard-stderr --help-option=--usage --no-info \
	    --version-string=$(BASE_VERSION) \
	    --name="Replay results from one or more .sarif files as if they were GCC diagnostics" \
	    $(d_diag)/$(PF)/bin/sarif-replay$(pkg_ver) > debian/sarif-replay.1; \
	fi
	cp debian/sarif-replay.1 \
		$(d_diag)/$(PF)/share/man/man1/$(cmd_prefix)sarif-replay$(pkg_ver).1
	dh_link -p$(p_diag) \
		$(PF)/share/man/man1/$(cmd_prefix)sarif-replay$(pkg_ver).1 \
		$(PF)/share/man/man1/sarif-replay$(pkg_ver).1

ifeq (,$(findstring nostrip,$(DEB_BUILD_OPTONS)))
	$(DWZ) \
	  $(d_diag)/$(PF)/bin/$(cmd_prefix)sarif-replay$(pkg_ver)
endif
	dh_strip -p$(p_diag)

	$(ignshld)$(cross_shlibdeps) dh_shlibdeps -p$(p_diag) \
		-L$(p_diaglib) \
		$(if $(filter yes, $(with_common_libs)),,-- -Ldebian/shlibs.common$(2))

	mkdir -p $(d_diag)/usr/share/lintian/overrides
	echo '$(p_diag) binary: hardening-no-pie' \
	  > $(d_diag)/usr/share/lintian/overrides/$(p_diag)

	debian/dh_doclink -p$(p_diag) $(p_base)

	echo $(p_diag) >> debian/arch_binaries

	trap '' 1 2 3 15; touch $@; mv $(install_stamp)-tmp $(install_stamp)
	touch $@

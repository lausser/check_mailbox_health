## Process this file with automake to produce Makefile.in

SED=/bin/sed
GREP=/bin/grep
CAT=/bin/cat
ECHO=/bin/echo

# --enable-standalone 1
# --disable-standalone 0
# ... 0
if DISABLE_STANDALONE
STANDALONE = "no"
else
STANDALONE = "yes"
endif

SUFFIXES = .pl .pm .sh

VPATH=$(top_srcdir) $(top_srcdir)/plugins-scripts $(top_srcdir)/plugins-scripts/t

libexec_SCRIPTS=check_mailbox_health
MY_MODULES=
GL_MODULES=\
  GLPlugin.pm
EXTRA_MODULES=\
  Classes/Device.pm \
  Classes/Mailserver.pm \
  Classes/MAIL.pm \
  Classes/IMAP.pm
EXTRA_DIST=check_mailbox_health.pl $(EXTRA_MODULES)

CLEANFILES=$(libexec_SCRIPTS)

AM_INSTALL_PROGRAM_FLAGS=@INSTALL_OPTS@

.pm :
	$(AWK) -f ./subst $< > $@
	chmod +x $@

.pl :
	$(AWK) -f ./subst $< > $@
	chmod +x $@

.sh :
	$(AWK) -f ./subst $< > $@
	chmod +x $@

$(libexec_SCRIPTS) : $(EXTRA_DIST)
	$(ECHO) "#! #PERL# -w" | $(AWK) -f ./subst > $@
	$(ECHO) >> $@
	if [ ${STANDALONE} == "yes" ]; then \
		for m in ${GL_MODULES}; do \
			$(SED) -e 's/^1;//g' < $$m | $(SED) -e '/^__END__/,$$d' | $(AWK) -f ./subst >> $@; \
		done \
	fi
	for m in ${EXTRA_MODULES}; do \
		$(SED) -e 's/^1;//g' < $$m | $(SED) -e '/^__END__/,$$d' | $(AWK) -f ./subst >> $@; \
	done
	$(ECHO) "package main;" >> $@
	if [ ${STANDALONE} == "no" ]; then \
		for m in ${GL_MODULES}; do \
			$(ECHO) "use `$(ECHO) $$m | $(SED) -s 's/\.pm$$//g'`;" >> $@; \
		done \
	fi
	$(CAT) check_mailbox_health.pl | $(AWK) -f ./subst >> $@
	chmod +x $@

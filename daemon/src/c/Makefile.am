LIBS=
bin_PROGRAMS=splayd jobd splay_core misc_core data_bits_core
# TODO find a way to dinamically recognize lua version
splayd_SOURCES        =splayd.c splay_lib.c
splayd_LDADD          =-llua5.1
jobd_SOURCES          =jobd.c splay_lib.c
jobd_LDADD            =-llua5.1
splay_core_SOURCES    =splay.c
splay_core_CFLAGS     =-fpic
splay_core_LDFLAGS    =-shared
misc_core_SOURCES     =misc.c
misc_core_CFLAGS      =-fpic
misc_core_LDFLAGS     =-shared -lm
data_bits_core_SOURCES=data_bits.c
data_bits_core_CFLAGS =-fpic
data_bits_core_LDFLAGS=-shared -lm

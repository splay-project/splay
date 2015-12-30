LIBS=
bin_PROGRAMS=splayd jobd splay_core.so misc_core.so data_bits_core.so
# TODO find a way to dinamically recognize lua version
splayd_SOURCES           =splayd.c splay_lib.c
splayd_LDADD             =-llua5.1
jobd_SOURCES             =jobd.c splay_lib.c
jobd_LDADD               =-llua5.1
splay_core_so_SOURCES    =splay.c
splay_core_so_CFLAGS     =-fpic
splay_core_so_LDFLAGS    =-shared
misc_core_so_SOURCES     =misc.c
misc_core_so_CFLAGS      =-fpic
misc_core_so_LDFLAGS     =-shared -lm
data_bits_core_so_SOURCES=data_bits.c
data_bits_core_so_CFLAGS =-fpic
data_bits_core_so_LDFLAGS=-shared -lm

#include <config.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>
#include <utime.h>
int main (argc, argv)
int argc;
char **argv;
{
if (argc != 2){
    fprintf (stderr, "Usage: poke file\n");
    exit (1);
}
if (utime (argv[1], NULL) < 0) {
    perror ("utime");
    exit (1);
}
exit (0);
}

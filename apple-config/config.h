/* config.h - Generated for Apple platforms (iOS/macOS/tvOS) */

#ifndef _LIBNFS_CONFIG_H_
#define _LIBNFS_CONFIG_H_

#include <TargetConditionals.h>

/* Define to 1 if you have the <arpa/inet.h> header file. */
#define HAVE_ARPA_INET_H 1

/* Define to 1 if you have the <dlfcn.h> header file. */
#define HAVE_DLFCN_H 1

/* Define to 1 if you have the <inttypes.h> header file. */
#define HAVE_INTTYPES_H 1

/* Define to 1 if you have the <memory.h> header file. */
#define HAVE_MEMORY_H 1

/* Define to 1 if you have the <netdb.h> header file. */
#define HAVE_NETDB_H 1

/* Define to 1 if you have the <netinet/in.h> header file. */
#define HAVE_NETINET_IN_H 1

/* Define to 1 if you have the <netinet/tcp.h> header file. */
#define HAVE_NETINET_TCP_H 1

/* Define to 1 if you have the <net/if.h> header file. */
#define HAVE_NET_IF_H 1

/* Define to 1 if you have the <poll.h> header file. */
#define HAVE_POLL_H 1

/* Define to 1 if you have the <pwd.h> header file. */
#define HAVE_PWD_H 1

/* Whether sockaddr struct has sa_len */
#define HAVE_SOCKADDR_LEN 1

/* Whether we have sockaddr_storage */
#define HAVE_SOCKADDR_STORAGE 1

/* Define to 1 if you have the <stdint.h> header file. */
#define HAVE_STDINT_H 1

/* Define to 1 if you have the <stdlib.h> header file. */
#define HAVE_STDLIB_H 1

/* Define to 1 if you have the <stdatomic.h> header file. */
#define HAVE_STDATOMIC_H 1

/* Define to 1 if you have the <strings.h> header file. */
#define HAVE_STRINGS_H 1

/* Define to 1 if you have the <string.h> header file. */
#define HAVE_STRING_H 1

/* Define to 1 if you have the <sys/filio.h> header file. */
#define HAVE_SYS_FILIO_H 1

/* Define to 1 if you have the <sys/ioctl.h> header file. */
#define HAVE_SYS_IOCTL_H 1

/* Define to 1 if you have the <sys/socket.h> header file. */
#define HAVE_SYS_SOCKET_H 1

/* Define to 1 if you have the <sys/statvfs.h> header file. */
#define HAVE_SYS_STATVFS_H 1

/* Define to 1 if you have the <sys/stat.h> header file. */
#define HAVE_SYS_STAT_H 1

/* Define to 1 if you have the <sys/time.h> header file. */
#define HAVE_SYS_TIME_H 1

/* Define to 1 if you have the <sys/types.h> header file. */
#define HAVE_SYS_TYPES_H 1

/* Define to 1 if you have the <sys/uio.h> header file. */
#define HAVE_SYS_UIO_H 1

/* Define to 1 if you have the <unistd.h> header file. */
#define HAVE_UNISTD_H 1

/* Define to 1 if you have the <utime.h> header file. */
#define HAVE_UTIME_H 1

/* Define to 1 if you have the <signal.h> header file. */
#define HAVE_SIGNAL_H 1

/* Define to 1 if you have the <sys/utsname.h> header file. */
#define HAVE_SYS_UTSNAME_H 1

/* Define to 1 if you have the <dispatch/dispatch.h> header file. */
#define HAVE_DISPATCH_DISPATCH_H 1

/* Whether pthread library is present */
#define HAVE_PTHREAD 1

/* Define to 1 if pthread_threadid_np() exists. */
#define HAVE_PTHREAD_THREADID_NP 1

/* Enable large inode numbers on Mac OS X 10.5. */
#ifndef _DARWIN_USE_64_BIT_INODE
# define _DARWIN_USE_64_BIT_INODE 1
#endif

/* macOS does not have sys/sysmacros.h, sys/vfs.h, SO_BINDTODEVICE, sys/sockio.h */
/* #undef HAVE_SYS_SYSMACROS_H */
/* #undef HAVE_SYS_VFS_H */
/* #undef HAVE_SO_BINDTODEVICE */
/* #undef HAVE_CLOCK_GETTIME */
/* #undef HAVE_STRUCT_STAT_ST_MTIM_TV_NSEC */
/* #undef HAVE_TLS */
/* #undef HAVE_TALLOC_TEVENT */
/* #undef HAVE_LIBKRB5 */
/* #undef HAVE_MULTITHREADING */

#if TARGET_OS_OSX
#define HAVE_SYS_SOCKIO_H 1
#endif

#endif /* _LIBNFS_CONFIG_H_ */

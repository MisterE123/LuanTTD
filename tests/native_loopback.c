/* Optional test-only preload: on restricted hosts with no Unix-domain socket
 * access, limit the disposable X server TCP listener to localhost. It is
 * intentionally preloaded only into Xvfb, never Luanti or the parent shell. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <netinet/in.h>
#include <sys/socket.h>

int bind(int fd, const struct sockaddr *a, socklen_t n)
{
    int (*original)(int,const struct sockaddr*,socklen_t)=dlsym(RTLD_NEXT,"bind");
    if (a && a->sa_family==AF_INET && n>=sizeof(struct sockaddr_in)) {
        struct sockaddr_in v=*(const struct sockaddr_in*)a;
        v.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
        return original(fd,(const struct sockaddr*)&v,sizeof(v));
    }
    if (a && a->sa_family==AF_INET6 && n>=sizeof(struct sockaddr_in6)) {
        struct sockaddr_in6 v=*(const struct sockaddr_in6*)a;
        v.sin6_addr=in6addr_loopback;
        return original(fd,(const struct sockaddr*)&v,sizeof(v));
    }
    return original(fd,a,n);
}

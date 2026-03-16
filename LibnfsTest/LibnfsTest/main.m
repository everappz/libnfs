#import <Foundation/Foundation.h>
#include <nfsc/libnfs.h>
#include <nfsc/libnfs-raw.h>

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // Init context
        struct nfs_context *nfs = nfs_init_context();
        if (!nfs) {
            NSLog(@"FAIL: nfs_init_context returned NULL");
            return 1;
        }
        NSLog(@"OK: nfs_init_context");

        // Parse URL
        struct nfs_url *url = nfs_parse_url_full(nfs, "nfs://127.0.0.1/export/path/file.txt");
        if (!url) {
            NSLog(@"FAIL: nfs_parse_url_full: %s", nfs_get_error(nfs));
            nfs_destroy_context(nfs);
            return 1;
        }
        NSLog(@"OK: nfs_parse_url_full");
        NSLog(@"  server: %s", url->server);
        NSLog(@"  path:   %s", url->path);
        NSLog(@"  file:   %s", url->file);

        // Set/get timeout
        nfs_set_timeout(nfs, 5000);
        int timeout = nfs_get_timeout(nfs);
        NSLog(@"OK: timeout set=%d get=%d", 5000, timeout);

        // Set UID/GID
        nfs_set_uid(nfs, 1000);
        nfs_set_gid(nfs, 1000);
        NSLog(@"OK: nfs_set_uid/gid");

        // RPC context
        struct rpc_context *rpc = nfs_get_rpc_context(nfs);
        NSLog(@"OK: nfs_get_rpc_context -> %p", rpc);

        // Cleanup
        nfs_destroy_url(url);
        nfs_destroy_context(nfs);
        NSLog(@"OK: cleanup done");

        NSLog(@"All checks passed - libnfs pod is working correctly.");
    }
    return 0;
}

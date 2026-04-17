/*
 NFSContext.m

 Created by Artem Meleshko on 2026-03-22.

 MIT License

 Copyright (c) 2026 Artem Meleshko

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.

 While NFSClient source code shipped with project is MIT licensed,
 but libnfs which is LGPL v2.1.
 */

#import "NFSContext.h"
#include <nfsc/libnfs.h>
#include <sys/stat.h>
#include <poll.h>
#include <fcntl.h>

NSString *const LNFSErrorDomain = @"LNFSErrorDomain";

static const size_t kDefaultChunkSize = 1048576; // 1 MB

@interface LNFSFileItem (Internal)

+ (instancetype)itemWithName:(NSString *)name
                        path:(NSString *)path
                        mode:(uint64_t)nfsMode
                        size:(uint64_t)size
                       inode:(uint64_t)inode
                       nlink:(uint64_t)nlink
                       atime:(uint64_t)atime
                   atimeNsec:(uint64_t)atimeNsec
                       mtime:(uint64_t)mtime
                   mtimeNsec:(uint64_t)mtimeNsec
                       ctime:(uint64_t)ctime
                   ctimeNsec:(uint64_t)ctimeNsec;

@end

#pragma mark -

@interface LNFSContext () {
    struct nfs_context *_nfs;
    NSRecursiveLock *_lock;
}
@end

@implementation LNFSContext

- (instancetype)init {
    self = [super init];
    if (self) {
        _lock = [[NSRecursiveLock alloc] init];
        _timeout = 60.0;
        _nfs = nfs_init_context();
    }
    return self;
}

- (void)dealloc {
    if (_nfs) {
        if (nfs_get_fd(_nfs) >= 0) {
            nfs_umount(_nfs);
        }
        nfs_destroy_context(_nfs);
        _nfs = NULL;
    }
}

#pragma mark - Error helpers

- (NSError *)errorWithCode:(int)code {
    [_lock lock];
    NSString *message = nil;
    if (_nfs) {
        const char *err = nfs_get_error(_nfs);
        if (err) {
            message = [NSString stringWithUTF8String:err];
        }
    }
    [_lock unlock];
    if (!message) {
        message = [NSString stringWithFormat:@"NFS error %d", code];
    }
    return [NSError errorWithDomain:LNFSErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

+ (NSError *)errorWithMessage:(NSString *)message code:(int)code {
    return [NSError errorWithDomain:LNFSErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

#pragma mark - Connection

// Fix bug #2: use nfs_get_fd() instead of accessing struct internals
- (BOOL)isConnected {
    [_lock lock];
    BOOL connected = (_nfs != NULL && nfs_get_fd(_nfs) >= 0);
    [_lock unlock];
    return connected;
}

- (BOOL)connectToServer:(NSString *)server
                   port:(int)port
                 export:(NSString *)exportName
                  error:(NSError **)error
{
    [_lock lock];

    if (!_nfs) {
        _nfs = nfs_init_context();
        if (!_nfs) {
            [_lock unlock];
            if (error) *error = [LNFSContext errorWithMessage:@"Failed to create NFS context" code:-ENOMEM];
            return NO;
        }
    }

    nfs_set_timeout(_nfs, (int)(self.timeout * 1000));
    nfs_set_uid(_nfs, self.uid);
    nfs_set_gid(_nfs, self.gid);

    if (port > 0) {
        nfs_set_nfsport(_nfs, port);
        nfs_set_mountport(_nfs, port);
    }

    int ret = nfs_mount(_nfs, [server UTF8String], [exportName UTF8String]);
    [_lock unlock];

    if (ret != 0) {
        if (error) *error = [self errorWithCode:ret];
        return NO;
    }
    return YES;
}

- (BOOL)disconnectWithError:(NSError **)error {
    [_lock lock];
    if (_nfs) {
        if (nfs_get_fd(_nfs) >= 0) {
            nfs_umount(_nfs);
        }
        nfs_destroy_context(_nfs);
        _nfs = NULL;
    }
    [_lock unlock];
    return YES;
}

#pragma mark - Stat

- (nullable LNFSFileItem *)statItemAtPath:(NSString *)path error:(NSError **)error {
    [_lock lock];

    if (!_nfs) {
        [_lock unlock];
        if (error) *error = [LNFSContext errorWithMessage:@"Not connected" code:-ENOTCONN];
        return nil;
    }

    struct nfs_stat_64 st;
    memset(&st, 0, sizeof(st));
    int ret = nfs_stat64(_nfs, [path UTF8String], &st);
    [_lock unlock];

    if (ret != 0) {
        if (error) *error = [self errorWithCode:ret];
        return nil;
    }

    NSString *name = [path lastPathComponent];
    if ([name length] == 0) name = @"/";

    return [LNFSFileItem itemWithName:name
                                 path:path
                                 mode:st.nfs_mode
                                 size:st.nfs_size
                                inode:st.nfs_ino
                                nlink:st.nfs_nlink
                                atime:st.nfs_atime
                            atimeNsec:st.nfs_atime_nsec
                                mtime:st.nfs_mtime
                            mtimeNsec:st.nfs_mtime_nsec
                                ctime:st.nfs_ctime
                            ctimeNsec:st.nfs_ctime_nsec];
}

#pragma mark - Statvfs

// Fix bug #3: use nfs_statvfs64 and nfs_statvfs_64 struct
- (nullable NSDictionary<NSFileAttributeKey, id> *)statvfs64AtPath:(NSString *)path
                                                             error:(NSError **)error
{
    [_lock lock];

    if (!_nfs) {
        [_lock unlock];
        if (error) *error = [LNFSContext errorWithMessage:@"Not connected" code:-ENOTCONN];
        return nil;
    }

    struct nfs_statvfs_64 svfs;
    memset(&svfs, 0, sizeof(svfs));
    int ret = nfs_statvfs64(_nfs, [path UTF8String], &svfs);
    [_lock unlock];

    if (ret != 0) {
        if (error) *error = [self errorWithCode:ret];
        return nil;
    }

    return @{
        NSFileSystemSize: @(svfs.f_blocks * svfs.f_frsize),
        NSFileSystemFreeSize: @(svfs.f_bfree * svfs.f_frsize),
        NSFileSystemNodes: @(svfs.f_files),
        NSFileSystemFreeNodes: @(svfs.f_ffree),
    };
}

#pragma mark - Directory operations

- (BOOL)mkdirAtPath:(NSString *)path error:(NSError **)error {
    [_lock lock];

    if (!_nfs) {
        [_lock unlock];
        if (error) *error = [LNFSContext errorWithMessage:@"Not connected" code:-ENOTCONN];
        return NO;
    }

    int ret = nfs_mkdir(_nfs, [path UTF8String]);
    [_lock unlock];

    if (ret != 0) {
        if (error) *error = [self errorWithCode:ret];
        return NO;
    }
    return YES;
}

- (BOOL)rmdirAtPath:(NSString *)path error:(NSError **)error {
    [_lock lock];

    if (!_nfs) {
        [_lock unlock];
        if (error) *error = [LNFSContext errorWithMessage:@"Not connected" code:-ENOTCONN];
        return NO;
    }

    int ret = nfs_rmdir(_nfs, [path UTF8String]);
    [_lock unlock];

    if (ret != 0) {
        if (error) *error = [self errorWithCode:ret];
        return NO;
    }
    return YES;
}

- (nullable NSArray<LNFSFileItem *> *)contentsOfDirectoryAtPath:(NSString *)path
                                                          error:(NSError **)error
{
    [_lock lock];

    if (!_nfs) {
        [_lock unlock];
        if (error) *error = [LNFSContext errorWithMessage:@"Not connected" code:-ENOTCONN];
        return nil;
    }

    struct nfsdir *nfsdir = NULL;
    int ret = nfs_opendir(_nfs, [path UTF8String], &nfsdir);
    if (ret != 0) {
        [_lock unlock];
        if (error) *error = [self errorWithCode:ret];
        return nil;
    }

    NSMutableArray<LNFSFileItem *> *items = [NSMutableArray array];

    struct nfsdirent *ent;
    while ((ent = nfs_readdir(_nfs, nfsdir)) != NULL) {
        NSString *name = [NSString stringWithUTF8String:ent->name];
        if ([name isEqualToString:@"."] || [name isEqualToString:@".."]) {
            continue;
        }

        NSString *entPath;
        if ([path isEqualToString:@"/"] || [path isEqualToString:@""]) {
            entPath = [NSString stringWithFormat:@"/%@", name];
        } else {
            entPath = [path stringByAppendingPathComponent:name];
        }

        LNFSFileItem *item = [LNFSFileItem itemWithName:name
                                                    path:entPath
                                                    mode:ent->mode
                                                    size:ent->size
                                                   inode:ent->inode
                                                   nlink:ent->nlink
                                                   atime:(uint64_t)ent->atime.tv_sec
                                               atimeNsec:(uint64_t)ent->atime_nsec
                                                   mtime:(uint64_t)ent->mtime.tv_sec
                                               mtimeNsec:(uint64_t)ent->mtime_nsec
                                                   ctime:(uint64_t)ent->ctime.tv_sec
                                               ctimeNsec:(uint64_t)ent->ctime_nsec];
        [items addObject:item];
    }

    nfs_closedir(_nfs, nfsdir);
    [_lock unlock];

    return items;
}

#pragma mark - File operations

- (BOOL)unlinkAtPath:(NSString *)path error:(NSError **)error {
    [_lock lock];

    if (!_nfs) {
        [_lock unlock];
        if (error) *error = [LNFSContext errorWithMessage:@"Not connected" code:-ENOTCONN];
        return NO;
    }

    int ret = nfs_unlink(_nfs, [path UTF8String]);
    [_lock unlock];

    if (ret != 0) {
        if (error) *error = [self errorWithCode:ret];
        return NO;
    }
    return YES;
}

- (BOOL)renameFrom:(NSString *)oldPath to:(NSString *)newPath error:(NSError **)error {
    [_lock lock];

    if (!_nfs) {
        [_lock unlock];
        if (error) *error = [LNFSContext errorWithMessage:@"Not connected" code:-ENOTCONN];
        return NO;
    }

    int ret = nfs_rename(_nfs, [oldPath UTF8String], [newPath UTF8String]);
    [_lock unlock];

    if (ret != 0) {
        if (error) *error = [self errorWithCode:ret];
        return NO;
    }
    return YES;
}

- (BOOL)truncateAtPath:(NSString *)path offset:(uint64_t)offset error:(NSError **)error {
    [_lock lock];

    if (!_nfs) {
        [_lock unlock];
        if (error) *error = [LNFSContext errorWithMessage:@"Not connected" code:-ENOTCONN];
        return NO;
    }

    int ret = nfs_truncate(_nfs, [path UTF8String], offset);
    [_lock unlock];

    if (ret != 0) {
        if (error) *error = [self errorWithCode:ret];
        return NO;
    }
    return YES;
}

- (nullable NSString *)readlinkAtPath:(NSString *)path error:(NSError **)error {
    [_lock lock];

    if (!_nfs) {
        [_lock unlock];
        if (error) *error = [LNFSContext errorWithMessage:@"Not connected" code:-ENOTCONN];
        return nil;
    }

    char *buf = NULL;
    int ret = nfs_readlink2(_nfs, [path UTF8String], &buf);
    [_lock unlock];

    if (ret != 0) {
        if (error) *error = [self errorWithCode:ret];
        return nil;
    }

    NSString *result = buf ? [NSString stringWithUTF8String:buf] : @"";
    free(buf);
    return result;
}

#pragma mark - File I/O

- (nullable NSData *)readFileAtPath:(NSString *)path
                             offset:(int64_t)offset
                             length:(int64_t)length
                           progress:(BOOL(^ _Nullable)(int64_t bytes, int64_t total))progress
                              error:(NSError **)error
{
    [_lock lock];

    if (!_nfs) {
        [_lock unlock];
        if (error) *error = [LNFSContext errorWithMessage:@"Not connected" code:-ENOTCONN];
        return nil;
    }

    struct nfsfh *nfsfh = NULL;
    int ret = nfs_open(_nfs, [path UTF8String], O_RDONLY, &nfsfh);
    if (ret != 0) {
        [_lock unlock];
        if (error) *error = [self errorWithCode:ret];
        return nil;
    }

    // Get file size if length not specified
    int64_t totalSize = length;
    if (totalSize <= 0) {
        struct nfs_stat_64 st;
        memset(&st, 0, sizeof(st));
        ret = nfs_fstat64(_nfs, nfsfh, &st);
        if (ret != 0) {
            nfs_close(_nfs, nfsfh);
            [_lock unlock];
            if (error) *error = [self errorWithCode:ret];
            return nil;
        }
        totalSize = (int64_t)st.nfs_size - offset;
        if (totalSize <= 0) {
            nfs_close(_nfs, nfsfh);
            [_lock unlock];
            return [NSData data];
        }
    }

    size_t chunkSize = nfs_get_readmax(_nfs);
    if (chunkSize == 0 || chunkSize > kDefaultChunkSize) {
        chunkSize = kDefaultChunkSize;
    }

    NSMutableData *result = [NSMutableData dataWithCapacity:(NSUInteger)totalSize];
    int64_t bytesRead = 0;
    uint64_t currentOffset = (uint64_t)offset;

    while (bytesRead < totalSize) {
        size_t toRead = (size_t)(totalSize - bytesRead);
        if (toRead > chunkSize) toRead = chunkSize;

        uint8_t *buf = malloc(toRead);
        if (!buf) {
            nfs_close(_nfs, nfsfh);
            [_lock unlock];
            if (error) *error = [LNFSContext errorWithMessage:@"Out of memory" code:-ENOMEM];
            return nil;
        }

        int nread = nfs_pread(_nfs, nfsfh, buf, toRead, currentOffset);
        if (nread < 0) {
            free(buf);
            nfs_close(_nfs, nfsfh);
            [_lock unlock];
            if (error) *error = [self errorWithCode:nread];
            return nil;
        }

        if (nread == 0) {
            free(buf);
            break; // EOF
        }

        [result appendBytes:buf length:(NSUInteger)nread];
        free(buf);

        bytesRead += nread;
        currentOffset += (uint64_t)nread;

        if (progress) {
            if (!progress(bytesRead, totalSize)) {
                nfs_close(_nfs, nfsfh);
                [_lock unlock];
                if (error) *error = [LNFSContext errorWithMessage:@"Cancelled" code:-ECANCELED];
                return nil;
            }
        }
    }

    nfs_close(_nfs, nfsfh);
    [_lock unlock];

    return result;
}

- (BOOL)readFileAtPath:(NSString *)path
             toFileURL:(NSURL *)localURL
              progress:(BOOL(^ _Nullable)(int64_t bytes, int64_t total))progress
                 error:(NSError **)error
{
    [_lock lock];

    if (!_nfs) {
        [_lock unlock];
        if (error) *error = [LNFSContext errorWithMessage:@"Not connected" code:-ENOTCONN];
        return NO;
    }

    struct nfsfh *nfsfh = NULL;
    int ret = nfs_open(_nfs, [path UTF8String], O_RDONLY, &nfsfh);
    if (ret != 0) {
        if (error) *error = [self errorWithCode:ret];
        [_lock unlock];
        return NO;
    }

    struct nfs_stat_64 st;
    memset(&st, 0, sizeof(st));
    ret = nfs_fstat64(_nfs, nfsfh, &st);
    if (ret != 0) {
        if (error) *error = [self errorWithCode:ret];
        nfs_close(_nfs, nfsfh);
        [_lock unlock];
        return NO;
    }

    int64_t totalSize = (int64_t)st.nfs_size;

    // Create/truncate local file
    [[NSFileManager defaultManager] createFileAtPath:[localURL path]
                                            contents:nil
                                          attributes:nil];
    NSError *localError = nil;
    NSFileHandle *localFH = [NSFileHandle fileHandleForWritingToURL:localURL
                                                              error:&localError];
    if (!localFH) {
        nfs_close(_nfs, nfsfh);
        [_lock unlock];
        if (error) *error = localError ?: [LNFSContext errorWithMessage:@"Failed to create local file" code:-EIO];
        return NO;
    }

    size_t chunkSize = nfs_get_readmax(_nfs);
    if (chunkSize == 0 || chunkSize > kDefaultChunkSize) {
        chunkSize = kDefaultChunkSize;
    }

    int64_t bytesRead = 0;
    uint64_t currentOffset = 0;
    BOOL success = YES;

    while (bytesRead < totalSize) {
        size_t toRead = (size_t)(totalSize - bytesRead);
        if (toRead > chunkSize) toRead = chunkSize;

        uint8_t *buf = malloc(toRead);
        if (!buf) {
            if (error) *error = [LNFSContext errorWithMessage:@"Out of memory" code:-ENOMEM];
            success = NO;
            break;
        }

        int nread = nfs_pread(_nfs, nfsfh, buf, toRead, currentOffset);
        if (nread < 0) {
            free(buf);
            if (error) *error = [self errorWithCode:nread];
            success = NO;
            break;
        }

        if (nread == 0) {
            free(buf);
            break; // EOF
        }

        [localFH writeData:[NSData dataWithBytesNoCopy:buf
                                                length:(NSUInteger)nread
                                          freeWhenDone:YES]];

        bytesRead += nread;
        currentOffset += (uint64_t)nread;

        if (progress) {
            if (!progress(bytesRead, totalSize)) {
                if (error) *error = [LNFSContext errorWithMessage:@"Cancelled" code:-ECANCELED];
                success = NO;
                break;
            }
        }
    }

    nfs_close(_nfs, nfsfh);
    [_lock unlock];
    [localFH closeFile];

    if (!success) {
        [[NSFileManager defaultManager] removeItemAtURL:localURL error:nil];
    }

    return success;
}

// Fix bug #6: write actual data length, no padding
- (BOOL)writeData:(NSData *)data
           toPath:(NSString *)path
         progress:(BOOL(^ _Nullable)(int64_t bytes))progress
            error:(NSError **)error
{
    [_lock lock];

    if (!_nfs) {
        [_lock unlock];
        if (error) *error = [LNFSContext errorWithMessage:@"Not connected" code:-ENOTCONN];
        return NO;
    }

    struct nfsfh *nfsfh = NULL;
    int ret = nfs_open(_nfs, [path UTF8String], O_WRONLY | O_CREAT | O_TRUNC, &nfsfh);
    if (ret != 0) {
        [_lock unlock];
        if (error) *error = [self errorWithCode:ret];
        return NO;
    }

    size_t chunkSize = nfs_get_writemax(_nfs);
    if (chunkSize == 0 || chunkSize > kDefaultChunkSize) {
        chunkSize = kDefaultChunkSize;
    }

    const uint8_t *bytes = (const uint8_t *)[data bytes];
    int64_t totalSize = (int64_t)[data length];
    int64_t bytesWritten = 0;

    while (bytesWritten < totalSize) {
        // Fix bug #6: write only actual remaining bytes, no padding
        size_t toWrite = (size_t)(totalSize - bytesWritten);
        if (toWrite > chunkSize) toWrite = chunkSize;

        int nwritten = nfs_pwrite(_nfs, nfsfh, (void *)(bytes + bytesWritten),
                                  toWrite, (uint64_t)bytesWritten);
        if (nwritten < 0) {
            nfs_close(_nfs, nfsfh);
            [_lock unlock];
            if (error) *error = [self errorWithCode:nwritten];
            return NO;
        }

        bytesWritten += nwritten;

        if (progress) {
            if (!progress(bytesWritten)) {
                nfs_close(_nfs, nfsfh);
                [_lock unlock];
                if (error) *error = [LNFSContext errorWithMessage:@"Cancelled" code:-ECANCELED];
                return NO;
            }
        }
    }

    nfs_close(_nfs, nfsfh);
    [_lock unlock];

    return YES;
}

- (BOOL)writeData:(NSData *)data
            toPath:(NSString *)path
            offset:(uint64_t)offset
      bytesWritten:(uint64_t * _Nullable)bytesWrittenOut
          progress:(BOOL(^ _Nullable)(int64_t chunkBytesWritten, int64_t totalBytesWritten))progress
             error:(NSError **)error
{
    [_lock lock];

    if (!_nfs) {
        [_lock unlock];
        if (error) *error = [LNFSContext errorWithMessage:@"Not connected" code:-ENOTCONN];
        return NO;
    }

    struct nfsfh *nfsfh = NULL;
    int ret = nfs_open(_nfs, [path UTF8String], O_WRONLY | O_CREAT, &nfsfh);
    if (ret != 0) {
        [_lock unlock];
        if (error) *error = [self errorWithCode:ret];
        return NO;
    }

    size_t chunkSize = nfs_get_writemax(_nfs);
    if (chunkSize == 0 || chunkSize > kDefaultChunkSize) {
        chunkSize = kDefaultChunkSize;
    }

    const uint8_t *bytes = (const uint8_t *)data.bytes;
    int64_t totalSize = (int64_t)data.length;
    int64_t localBytesWritten = 0;
    uint64_t currentOffset = offset;

    while (localBytesWritten < totalSize) {
        size_t toWrite = (size_t)(totalSize - localBytesWritten);
        if (toWrite > chunkSize) {
            toWrite = chunkSize;
        }

        int nwritten = nfs_pwrite(_nfs,
                                  nfsfh,
                                  (void *)(bytes + localBytesWritten),
                                  toWrite,
                                  currentOffset);
        if (nwritten < 0) {
            nfs_close(_nfs, nfsfh);
            [_lock unlock];
            if (error) *error = [self errorWithCode:nwritten];
            return NO;
        }

        if (nwritten == 0) {
            nfs_close(_nfs, nfsfh);
            [_lock unlock];
            if (error) *error = [LNFSContext errorWithMessage:@"Write returned 0 bytes" code:-EIO];
            return NO;
        }

        localBytesWritten += nwritten;
        currentOffset += (uint64_t)nwritten;

        if (progress) {
            if (!progress(localBytesWritten, (int64_t)currentOffset)) {
                nfs_close(_nfs, nfsfh);
                [_lock unlock];
                if (error) *error = [LNFSContext errorWithMessage:@"Cancelled" code:-ECANCELED];
                return NO;
            }
        }
    }

    nfs_close(_nfs, nfsfh);
    [_lock unlock];

    if (bytesWrittenOut) {
        *bytesWrittenOut = currentOffset;
    }

    return YES;
}

@end

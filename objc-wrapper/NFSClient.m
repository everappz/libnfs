/*
 NFSClient.m

 Created by Artem Meleshko on 2026-03-23.

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

#import "NFSClient.h"
#import "NFSContext.h"
#include <nfsc/libnfs.h>
#include "libnfs-raw-mount.h"

static char kLNFSClientQueueSpecificKey;

@interface LNFSClient () {
    NSString *_host;
    int _port;
    LNFSContext *_context;
    NSString *_exportName;
    dispatch_queue_t _queue;
    int32_t _uid;
    int32_t _gid;
}
@end

@implementation LNFSClient

- (instancetype)initWithHost:(NSString *)host port:(int)port {
    self = [super init];
    if (self) {
        _host = [host copy];
        _port = port;
        _queue = dispatch_queue_create("com.libnfs.client", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(_queue, &kLNFSClientQueueSpecificKey, (__bridge void *)self, NULL);
        _timeout = 60.0;
        _uid = (int32_t)getuid();
        _gid = (int32_t)getgid();
    }
    return self;
}

- (int32_t)uid {
    return _uid;
}

- (void)setUid:(int32_t)uid {
    _uid = uid;
}

- (int32_t)gid {
    return _gid;
}

- (void)setGid:(int32_t)gid {
    _gid = gid;
}

- (BOOL)isConnected {
    if (dispatch_get_specific(&kLNFSClientQueueSpecificKey)) {
        return (_context != nil && [_context isConnected]);
    } else {
        __block BOOL connected = NO;
        dispatch_sync(_queue, ^{
            connected = (_context != nil && [_context isConnected]);
        });
        return connected;
    }
}

- (NSString *_Nullable)exportName {
    if (dispatch_get_specific(&kLNFSClientQueueSpecificKey)) {
        return _exportName;
    } else {
        __block NSString *name = nil;
        dispatch_sync(_queue, ^{
            name = _exportName;
        });
        return name;
    }
}

#pragma mark - Context management

- (LNFSContext *)createContext {
    LNFSContext *ctx = [[LNFSContext alloc] init];
    ctx.timeout = self.timeout;
    ctx.uid = _uid;
    ctx.gid = _gid;
    return ctx;
}

- (LNFSContext *_Nullable)connectedContext {
    if (dispatch_get_specific(&kLNFSClientQueueSpecificKey)) {
        LNFSContext *ctx = _context;
        return (ctx != nil && [ctx isConnected]) ? ctx : nil;
    } else {
        __block LNFSContext *result = nil;
        dispatch_sync(_queue, ^{
            LNFSContext *ctx = _context;
            if (ctx != nil && [ctx isConnected]) {
                result = ctx;
            }
        });
        return result;
    }
}

#pragma mark - Connection

- (void)connectToExport:(NSString *)exportName
             completion:(void(^)(NSError *))completion
{
    __weak typeof(self) weakSelf = self;
    dispatch_async(_queue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (completion) {
                completion([LNFSClient clientDeallocatedError]);
            }
            return;
        }

        if (strongSelf->_context != nil && strongSelf->_exportName != nil) {
            if (completion) {
                completion(nil);
            }
            return;
        }

        LNFSContext *ctx = [strongSelf createContext];

        NSError *error = nil;
        [ctx connectToServer:strongSelf->_host port:strongSelf->_port export:exportName error:&error];

        if ([ctx isConnected]) {
            strongSelf->_context = ctx;
            strongSelf->_exportName = [exportName copy];
        }

        if (completion) {
            completion(error);
        }
    });
}

- (void)disconnectFromExportWithCompletion:(void(^)(NSError *))completion {
    __weak typeof(self) weakSelf = self;
    dispatch_async(_queue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (completion) {
                completion(nil);
            }
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];
        if (!ctx) {
            if (completion) {
                completion(nil);
            }
            return;
        }

        NSError *error = nil;
        [ctx disconnectWithError:&error];

        strongSelf->_context = nil;
        strongSelf->_exportName = nil;

        if (completion) {
            completion(error);
        }
    });
}

- (void)listExportsWithCompletion:(void(^)(NSArray<NSString *> *, NSError *))completion {
    __weak typeof(self) weakSelf = self;
    dispatch_async(_queue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (completion) {
                completion(nil, [LNFSClient clientDeallocatedError]);
            }
            return;
        }

        struct exportnode *exports;
        if (strongSelf->_port > 0) {
            exports = mount_getexports_mountport([strongSelf->_host UTF8String], strongSelf->_port);
        } else {
            exports = mount_getexports([strongSelf->_host UTF8String]);
        }

        if (!exports) {
            NSError *error = [NSError errorWithDomain:LNFSErrorDomain
                                                 code:-EIO
                                             userInfo:@{NSLocalizedDescriptionKey: @"Failed to list exports"}];
            if (completion) {
                completion(nil, error);
            }
            return;
        }

        NSMutableArray<NSString *> *result = [NSMutableArray array];
        struct exportnode *node = exports;
        while (node) {
            if (node->ex_dir) {
                [result addObject:[NSString stringWithUTF8String:node->ex_dir]];
            }
            node = node->ex_next;
        }
        mount_free_export_list(exports);

        if (completion) {
            completion(result, nil);
        }
    });
}

#pragma mark - Directory operations

- (void)contentsOfDirectoryAtPath:(NSString *)path
                        recursive:(BOOL)recursive
                       completion:(void(^)(NSArray<LNFSFileItem *> *, NSError *))completion
{
    __weak typeof(self) weakSelf = self;
    dispatch_async(_queue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (completion) {
                completion(nil, [LNFSClient clientDeallocatedError]);
            }
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];
        if (!ctx) {
            if (completion) {
                completion(nil, [LNFSClient noContextError]);
            }
            return;
        }

        NSError *error = nil;
        NSArray<LNFSFileItem *> *items = [ctx contentsOfDirectoryAtPath:path error:&error];
        if (!items) {
            if (completion) {
                completion(nil, error);
            }
            return;
        }

        if (recursive) {
            NSMutableArray *allItems = [NSMutableArray arrayWithArray:items];
            for (LNFSFileItem *item in items) {
                if (item.isDirectory) {
                    NSArray *subItems = [ctx contentsOfDirectoryAtPath:item.path error:nil];
                    if (subItems) {
                        [strongSelf recursivelyAddContents:subItems
                                               fromContext:ctx
                                                   toArray:allItems];
                    }
                }
            }
            if (completion) {
                completion(allItems, nil);
            }
        } else {
            if (completion) {
                completion(items, nil);
            }
        }
    });
}

- (void)recursivelyAddContents:(NSArray<LNFSFileItem *> *)items
                   fromContext:(LNFSContext *)ctx
                       toArray:(NSMutableArray<LNFSFileItem *> *)array
{
    for (LNFSFileItem *item in items) {
        [array addObject:item];
        if (item.isDirectory) {
            NSArray *subItems = [ctx contentsOfDirectoryAtPath:item.path error:nil];
            if (subItems) {
                [self recursivelyAddContents:subItems fromContext:ctx toArray:array];
            }
        }
    }
}

- (void)createDirectoryAtPath:(NSString *)path
                   completion:(void(^)(NSError *))completion
{
    __weak typeof(self) weakSelf = self;
    dispatch_async(_queue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (completion) {
                completion([LNFSClient clientDeallocatedError]);
            }
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];
        if (!ctx) {
            if (completion) {
                completion([LNFSClient noContextError]);
            }
            return;
        }

        NSError *error = nil;
        [ctx mkdirAtPath:path error:&error];

        if (completion) {
            completion(error);
        }
    });
}

- (void)removeDirectoryAtPath:(NSString *)path
                    recursive:(BOOL)recursive
                   completion:(void(^)(NSError *))completion
{
    __weak typeof(self) weakSelf = self;
    dispatch_async(_queue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (completion) {
                completion([LNFSClient clientDeallocatedError]);
            }
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];
        if (!ctx) {
            if (completion) {
                completion([LNFSClient noContextError]);
            }
            return;
        }

        NSError *error = nil;
        if (recursive) {
            [strongSelf recursivelyRemoveDirectoryAtPath:path context:ctx error:&error];
        } else {
            [ctx rmdirAtPath:path error:&error];
        }

        if (completion) {
            completion(error);
        }
    });
}

- (BOOL)recursivelyRemoveDirectoryAtPath:(NSString *)path
                                 context:(LNFSContext *)ctx
                                   error:(NSError **)error
{
    NSArray<LNFSFileItem *> *items = [ctx contentsOfDirectoryAtPath:path error:error];
    if (!items) return NO;

    for (LNFSFileItem *item in items) {
        if (item.isDirectory) {
            if (![self recursivelyRemoveDirectoryAtPath:item.path context:ctx error:error]) {
                return NO;
            }
        } else {
            if (![ctx unlinkAtPath:item.path error:error]) {
                return NO;
            }
        }
    }

    return [ctx rmdirAtPath:path error:error];
}

#pragma mark - File attributes

- (void)attributesOfItemAtPath:(NSString *)path
                    completion:(void(^)(LNFSFileItem *, NSError *))completion
{
    __weak typeof(self) weakSelf = self;
    dispatch_async(_queue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (completion) {
                completion(nil, [LNFSClient clientDeallocatedError]);
            }
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];
        if (!ctx) {
            if (completion) {
                completion(nil, [LNFSClient noContextError]);
            }
            return;
        }

        NSError *error = nil;
        LNFSFileItem *item = [ctx statItemAtPath:path error:&error];

        if (completion) {
            completion(item, error);
        }
    });
}

- (void)attributesOfFileSystemForPath:(NSString *)path
                           completion:(void(^)(NSDictionary<NSFileAttributeKey,id> *, NSError *))completion
{
    __weak typeof(self) weakSelf = self;
    dispatch_async(_queue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (completion) {
                completion(nil, [LNFSClient clientDeallocatedError]);
            }
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];
        if (!ctx) {
            if (completion) {
                completion(nil, [LNFSClient noContextError]);
            }
            return;
        }

        NSError *error = nil;
        NSDictionary *attrs = [ctx statvfs64AtPath:path error:&error];

        if (completion) {
            completion(attrs, error);
        }
    });
}

- (void)destinationOfSymbolicLinkAtPath:(NSString *)path
                             completion:(void(^)(NSString *, NSError *))completion
{
    __weak typeof(self) weakSelf = self;
    dispatch_async(_queue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (completion) {
                completion(nil, [LNFSClient clientDeallocatedError]);
            }
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];
        if (!ctx) {
            if (completion) {
                completion(nil, [LNFSClient noContextError]);
            }
            return;
        }

        NSError *error = nil;
        NSString *dest = [ctx readlinkAtPath:path error:&error];

        if (completion) {
            completion(dest, error);
        }
    });
}

#pragma mark - File operations

- (void)removeFileAtPath:(NSString *)path
              completion:(void(^)(NSError *))completion
{
    __weak typeof(self) weakSelf = self;
    dispatch_async(_queue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (completion) {
                completion([LNFSClient clientDeallocatedError]);
            }
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];
        if (!ctx) {
            if (completion) {
                completion([LNFSClient noContextError]);
            }
            return;
        }

        NSError *error = nil;
        [ctx unlinkAtPath:path error:&error];

        if (completion) {
            completion(error);
        }
    });
}

- (void)removeItemAtPath:(NSString *)path
              completion:(void(^)(NSError *))completion
{
    __weak typeof(self) weakSelf = self;
    dispatch_async(_queue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (completion) {
                completion([LNFSClient clientDeallocatedError]);
            }
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];
        if (!ctx) {
            if (completion) {
                completion([LNFSClient noContextError]);
            }
            return;
        }

        NSError *error = nil;
        LNFSFileItem *item = [ctx statItemAtPath:path error:&error];
        if (!item) {
            if (completion) {
                completion(error);
            }
            return;
        }

        if (item.isDirectory) {
            [strongSelf recursivelyRemoveDirectoryAtPath:path context:ctx error:&error];
        } else {
            [ctx unlinkAtPath:path error:&error];
        }

        if (completion) {
            completion(error);
        }
    });
}

- (void)moveItemAtPath:(NSString *)from
                toPath:(NSString *)to
            completion:(void(^)(NSError *))completion
{
    __weak typeof(self) weakSelf = self;
    dispatch_async(_queue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (completion) {
                completion([LNFSClient clientDeallocatedError]);
            }
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];

        if (!ctx) {
            if (completion) {
                completion([LNFSClient noContextError]);
            }
            return;
        }

        NSError *error = nil;
        [ctx renameFrom:from to:to error:&error];

        if (completion) {
            completion(error);
        }
    });
}

- (void)truncateFileAtPath:(NSString *)path
                  toOffset:(uint64_t)offset
                completion:(void(^)(NSError *))completion
{
    __weak typeof(self) weakSelf = self;
    dispatch_async(_queue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (completion) {
                completion([LNFSClient clientDeallocatedError]);
            }
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];

        if (!ctx) {
            if (completion) {
                completion([LNFSClient noContextError]);
            }
            return;
        }

        NSError *error = nil;
        [ctx truncateAtPath:path offset:offset error:&error];

        if (completion) {
            completion(error);
        }
    });
}

#pragma mark - Read / Write

- (void)contentsAtPath:(NSString *)path
              progress:(BOOL(^ _Nullable)(int64_t, int64_t))progress
            completion:(void(^)(NSData *, NSError *))completion
{
    [self contentsAtPath:path offset:0 length:0 progress:progress completion:completion];
}

- (void)contentsAtPath:(NSString *)path
                offset:(int64_t)offset
                length:(int64_t)length
              progress:(BOOL(^ _Nullable)(int64_t, int64_t))progress
            completion:(void(^)(NSData *, NSError *))completion
{
    __weak typeof(self) weakSelf = self;
    dispatch_async(_queue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (completion) {
                completion(nil, [LNFSClient clientDeallocatedError]);
            }
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];

        if (!ctx) {
            if (completion) {
                completion(nil, [LNFSClient noContextError]);
            }
            return;
        }

        NSError *error = nil;
        NSData *data = [ctx readFileAtPath:path offset:offset length:length progress:progress error:&error];

        if (completion) {
            completion(data, error);
        }
    });
}

- (void)writeData:(NSData *)data
           toPath:(NSString *)path
         progress:(BOOL(^ _Nullable)(int64_t))progress
       completion:(void(^)(NSError *))completion
{
    __weak typeof(self) weakSelf = self;
    dispatch_async(_queue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (completion) {
                completion([LNFSClient clientDeallocatedError]);
            }
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];

        if (!ctx) {
            if (completion) {
                completion([LNFSClient noContextError]);
            }
            return;
        }

        NSError *error = nil;
        [ctx writeData:data toPath:path progress:progress error:&error];

        if (completion) {
            completion(error);
        }
    });
}

- (void)uploadItemAtURL:(NSURL *)url
                 toPath:(NSString *)path
               progress:(BOOL(^ _Nullable)(int64_t))progress
             completion:(void(^)(NSError *))completion
{
    __weak typeof(self) weakSelf = self;
    dispatch_async(_queue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (completion) {
                completion([LNFSClient clientDeallocatedError]);
            }
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];
        if (!ctx) {
            if (completion) {
                completion([LNFSClient noContextError]);
            }
            return;
        }

        NSError *error = nil;

        NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingFromURL:url error:&error];
        if (!fileHandle) {
            if (!error) {
                error = [NSError errorWithDomain:LNFSErrorDomain
                                            code:-EIO
                                        userInfo:@{NSLocalizedDescriptionKey: @"Failed to open local file"}];
            }
            if (completion) {
                completion(error);
            }
            return;
        }

        NSNumber *fileSizeValue = nil;
        if (![url getResourceValue:&fileSizeValue forKey:NSURLFileSizeKey error:&error]) {
            [fileHandle closeFile];
            if (!error) {
                error = [NSError errorWithDomain:LNFSErrorDomain
                                            code:-EIO
                                        userInfo:@{NSLocalizedDescriptionKey: @"Failed to get local file size"}];
            }
            if (completion) {
                completion(error);
            }
            return;
        }

        uint64_t totalSize = [fileSizeValue unsignedLongLongValue];
        uint64_t totalUploaded = 0;
        uint64_t remoteOffset = 0;

        // Start a fresh upload.
        [ctx truncateAtPath:path offset:0 error:nil];

        static const NSUInteger localChunkSize = 1024 * 1024; // 1 MB

        while (totalUploaded < totalSize) {
            @autoreleasepool {
                NSUInteger bytesToRead = (NSUInteger)MIN((uint64_t)localChunkSize, totalSize - totalUploaded);
                NSData *chunk = [fileHandle readDataOfLength:bytesToRead];

                if (chunk.length == 0) {
                    error = [NSError errorWithDomain:LNFSErrorDomain
                                                code:-EIO
                                            userInfo:@{NSLocalizedDescriptionKey: @"Unexpected end of local file during upload"}];
                    break;
                }

                uint64_t nextOffset = remoteOffset;
                BOOL success = [ctx writeData:chunk
                                       toPath:path
                                       offset:remoteOffset
                                 bytesWritten:&nextOffset
                                     progress:nil
                                        error:&error];
                if (!success) {
                    break;
                }

                remoteOffset = nextOffset;
                totalUploaded += (uint64_t)chunk.length;

                if (progress) {
                    if (!progress((int64_t)totalUploaded)) {
                        error = [NSError errorWithDomain:LNFSErrorDomain
                                                    code:-ECANCELED
                                                userInfo:@{NSLocalizedDescriptionKey: @"Cancelled"}];
                        break;
                    }
                }
            }
        }

        [fileHandle closeFile];

        if (completion) {
            completion(error);
        }
    });
}

- (void)downloadItemAtPath:(NSString *)path
                     toURL:(NSURL *)url
                  progress:(BOOL(^ _Nullable)(int64_t, int64_t))progress
                completion:(void(^)(NSError *))completion
{
    __weak typeof(self) weakSelf = self;
    dispatch_async(_queue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (completion) {
                completion([LNFSClient clientDeallocatedError]);
            }
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];

        if (!ctx) {
            if (completion) {
                completion([LNFSClient noContextError]);
            }
            return;
        }

        NSError *error = nil;
        [ctx readFileAtPath:path toFileURL:url progress:progress error:&error];

        if (completion) {
            completion(error);
        }
    });
}

#pragma mark - Helpers

+ (NSError *)noContextError {
    return [NSError errorWithDomain:LNFSErrorDomain
                               code:-ENOTCONN
                           userInfo:@{NSLocalizedDescriptionKey: @"Not connected to any export"}];
}

+ (NSError *)clientDeallocatedError {
    return [NSError errorWithDomain:LNFSErrorDomain
                               code:-ENOTCONN
                           userInfo:@{NSLocalizedDescriptionKey: @"Client was deallocated"}];
}

@end


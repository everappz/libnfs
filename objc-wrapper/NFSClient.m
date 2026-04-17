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
#include <sys/stat.h>
#include <unistd.h>
#include "libnfs-raw-mount.h"

static char kLNFSClientQueueSpecificKey;
static void *kLNFSClientQueueMarker = &kLNFSClientQueueMarker;

static char kLNFSClientCallbackQueueSpecificKey;
static void *kLNFSClientCallbackQueueMarker = &kLNFSClientCallbackQueueMarker;

static const NSUInteger kLNFSClientLocalChunkSize = 1024 * 1024; // 1 MB

@interface LNFSClient () {
    NSString *_host;
    int _port;
    LNFSContext *_context;
    NSString *_exportName;
    dispatch_queue_t _queue;
    dispatch_queue_t _callbackQueue;
    int32_t _uid;
    int32_t _gid;
    NSTimeInterval _timeout;
}
@end

@implementation LNFSClient

- (instancetype)initWithHost:(NSString *)host port:(int)port {
    self = [super init];
    if (self) {
        _host = [host copy];
        _port = port;
        _timeout = 60.0;

        _queue = dispatch_queue_create("com.libnfs.client", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(_queue,
                                    &kLNFSClientQueueSpecificKey,
                                    kLNFSClientQueueMarker,
                                    NULL);

        _callbackQueue = dispatch_queue_create("com.libnfs.client.callbacks", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(_callbackQueue,
                                    &kLNFSClientCallbackQueueSpecificKey,
                                    kLNFSClientCallbackQueueMarker,
                                    NULL);

        _uid = (int32_t)getuid();
        _gid = (int32_t)getgid();
    }
    return self;
}

#pragma mark - Queue helpers

- (BOOL)isOnClientQueue {
    return dispatch_get_specific(&kLNFSClientQueueSpecificKey) == kLNFSClientQueueMarker;
}

- (BOOL)isOnCallbackQueue {
    return dispatch_get_specific(&kLNFSClientCallbackQueueSpecificKey) == kLNFSClientCallbackQueueMarker;
}

- (void)asyncOnCallbackQueue:(dispatch_block_t)block {
    if (!block) return;

    if ([self isOnCallbackQueue]) {
        block();
    } else {
        dispatch_async(_callbackQueue, block);
    }
}

- (void)finishWithError:(NSError *)error
             completion:(void(^)(NSError *))completion
{
    if (!completion) return;

    [self asyncOnCallbackQueue:^{
        completion(error);
    }];
}

- (void)finishWithItems:(NSArray<LNFSFileItem *> *)items
                  error:(NSError *)error
             completion:(void(^)(NSArray<LNFSFileItem *> *, NSError *))completion
{
    if (!completion) return;

    [self asyncOnCallbackQueue:^{
        completion(items, error);
    }];
}

- (void)finishWithFileItem:(LNFSFileItem *)item
                     error:(NSError *)error
                completion:(void(^)(LNFSFileItem *, NSError *))completion
{
    if (!completion) return;

    [self asyncOnCallbackQueue:^{
        completion(item, error);
    }];
}

- (void)finishWithAttributes:(NSDictionary<NSFileAttributeKey, id> *)attributes
                       error:(NSError *)error
                  completion:(void(^)(NSDictionary<NSFileAttributeKey,id> *, NSError *))completion
{
    if (!completion) return;

    [self asyncOnCallbackQueue:^{
        completion(attributes, error);
    }];
}

- (void)finishWithString:(NSString *)string
                   error:(NSError *)error
              completion:(void(^)(NSString *, NSError *))completion
{
    if (!completion) return;

    [self asyncOnCallbackQueue:^{
        completion(string, error);
    }];
}

- (void)finishWithData:(NSData *)data
                 error:(NSError *)error
            completion:(void(^)(NSData *, NSError *))completion
{
    if (!completion) return;

    [self asyncOnCallbackQueue:^{
        completion(data, error);
    }];
}

- (void)finishWithExports:(NSArray<NSString *> *)exports
                    error:(NSError *)error
               completion:(void(^)(NSArray<NSString *> *, NSError *))completion
{
    if (!completion) return;

    [self asyncOnCallbackQueue:^{
        completion(exports, error);
    }];
}

#pragma mark - Property access

- (int32_t)uid {
    if ([self isOnClientQueue]) {
        return _uid;
    }

    __block int32_t value = 0;
    dispatch_sync(_queue, ^{
        value = self->_uid;
    });
    return value;
}

- (void)setUid:(int32_t)uid {
    if ([self isOnClientQueue]) {
        _uid = uid;
    } else {
        dispatch_sync(_queue, ^{
            self->_uid = uid;
        });
    }
}

- (int32_t)gid {
    if ([self isOnClientQueue]) {
        return _gid;
    }

    __block int32_t value = 0;
    dispatch_sync(_queue, ^{
        value = self->_gid;
    });
    return value;
}

- (void)setGid:(int32_t)gid {
    if ([self isOnClientQueue]) {
        _gid = gid;
    } else {
        dispatch_sync(_queue, ^{
            self->_gid = gid;
        });
    }
}

- (NSTimeInterval)timeout {
    if ([self isOnClientQueue]) {
        return _timeout;
    }

    __block NSTimeInterval value = 0;
    dispatch_sync(_queue, ^{
        value = self->_timeout;
    });
    return value;
}

- (void)setTimeout:(NSTimeInterval)timeout {
    if ([self isOnClientQueue]) {
        _timeout = timeout;
    } else {
        dispatch_sync(_queue, ^{
            self->_timeout = timeout;
        });
    }
}

- (BOOL)isConnected {
    if ([self isOnClientQueue]) {
        return (_context != nil && [_context isConnected]);
    }

    __block BOOL connected = NO;
    dispatch_sync(_queue, ^{
        connected = (self->_context != nil && [self->_context isConnected]);
    });
    return connected;
}

- (NSString *_Nullable)exportName {
    if ([self isOnClientQueue]) {
        return _exportName;
    }

    __block NSString *name = nil;
    dispatch_sync(_queue, ^{
        name = self->_exportName;
    });
    return name;
}

#pragma mark - Context management

- (LNFSContext *)createContext {
    LNFSContext *ctx = [[LNFSContext alloc] init];
    ctx.timeout = _timeout;
    ctx.uid = _uid;
    ctx.gid = _gid;
    return ctx;
}

- (LNFSContext *_Nullable)connectedContext {
    if ([self isOnClientQueue]) {
        LNFSContext *ctx = _context;
        return (ctx != nil && [ctx isConnected]) ? ctx : nil;
    }

    __block LNFSContext *result = nil;
    dispatch_sync(_queue, ^{
        LNFSContext *ctx = self->_context;
        if (ctx != nil && [ctx isConnected]) {
            result = ctx;
        }
    });
    return result;
}

#pragma mark - Recursive helpers

- (BOOL)recursivelyAddContents:(NSArray<LNFSFileItem *> *)items
                   fromContext:(LNFSContext *)ctx
                       toArray:(NSMutableArray<LNFSFileItem *> *)array
                  visitedPaths:(NSMutableSet<NSString *> *)visitedPaths
                         error:(NSError **)error
{
    for (LNFSFileItem *item in items) {
        if (item.path.length == 0) {
            continue;
        }

        [array addObject:item];

        if (!item.isDirectory) {
            continue;
        }

        if ([visitedPaths containsObject:item.path]) {
            continue;
        }
        [visitedPaths addObject:item.path];

        NSError *subError = nil;
        NSArray<LNFSFileItem *> *subItems = [ctx contentsOfDirectoryAtPath:item.path error:&subError];
        if (!subItems) {
            if (error) *error = subError;
            return NO;
        }

        if (![self recursivelyAddContents:subItems
                              fromContext:ctx
                                  toArray:array
                             visitedPaths:visitedPaths
                                    error:error]) {
            return NO;
        }
    }

    return YES;
}

- (BOOL)recursivelyRemoveDirectoryAtPath:(NSString *)path
                                 context:(LNFSContext *)ctx
                            visitedPaths:(NSMutableSet<NSString *> *)visitedPaths
                                   error:(NSError **)error
{
    if ([visitedPaths containsObject:path]) {
        if (error) {
            *error = [NSError errorWithDomain:LNFSErrorDomain
                                         code:-ELOOP
                                     userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Detected recursive directory loop at path %@", path]
            }];
        }
        return NO;
    }
    [visitedPaths addObject:path];

    NSArray<LNFSFileItem *> *items = [ctx contentsOfDirectoryAtPath:path error:error];
    if (!items) {
        return NO;
    }

    for (LNFSFileItem *item in items) {
        if (item.isDirectory) {
            if (![self recursivelyRemoveDirectoryAtPath:item.path
                                                context:ctx
                                           visitedPaths:visitedPaths
                                                  error:error]) {
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

#pragma mark - Connection

- (void)connectToExport:(NSString *)exportName
             completion:(void(^)(NSError *))completion
{
    __weak typeof(self) weakSelf = self;
    dispatch_queue_t callbackQueue = _callbackQueue;

    dispatch_async(_queue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (completion) {
                dispatch_async(callbackQueue, ^{
                    completion([LNFSClient clientDeallocatedError]);
                });
            }
            return;
        }

        if (strongSelf->_context != nil &&
            strongSelf->_exportName != nil &&
            [strongSelf->_context isConnected]) {
            NSError *alreadyConnectedError = nil;
            if (![strongSelf->_exportName isEqualToString:exportName]) {
                alreadyConnectedError = [NSError errorWithDomain:LNFSErrorDomain
                                                            code:-EALREADY
                                                        userInfo:@{
                    NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Already connected to export %@", strongSelf->_exportName]
                }];
            }
            [strongSelf finishWithError:alreadyConnectedError completion:completion];
            return;
        }

        LNFSContext *ctx = [strongSelf createContext];

        NSError *error = nil;
        BOOL success = [ctx connectToServer:strongSelf->_host
                                       port:strongSelf->_port
                                     export:exportName
                                      error:&error];
        if (success && [ctx isConnected]) {
            strongSelf->_context = ctx;
            strongSelf->_exportName = [exportName copy];
        }

        [strongSelf finishWithError:error completion:completion];
    });
}

- (void)disconnectFromExportWithCompletion:(void(^)(NSError *))completion {
    __weak typeof(self) weakSelf = self;
    dispatch_queue_t callbackQueue = _callbackQueue;

    dispatch_async(_queue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (completion) {
                dispatch_async(callbackQueue, ^{
                    completion(nil);
                });
            }
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];
        if (!ctx) {
            [strongSelf finishWithError:nil completion:completion];
            return;
        }

        NSError *error = nil;
        [ctx disconnectWithError:&error];

        strongSelf->_context = nil;
        strongSelf->_exportName = nil;

        [strongSelf finishWithError:error completion:completion];
    });
}

- (void)listExportsWithCompletion:(void(^)(NSArray<NSString *> *, NSError *))completion {
    __weak typeof(self) weakSelf = self;
    dispatch_queue_t callbackQueue = _callbackQueue;

    dispatch_async(_queue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (completion) {
                dispatch_async(callbackQueue, ^{
                    completion(nil, [LNFSClient clientDeallocatedError]);
                });
            }
            return;
        }

        struct exportnode *exports = NULL;
        if (strongSelf->_port > 0) {
            exports = mount_getexports_mountport([strongSelf->_host UTF8String], strongSelf->_port);
        } else {
            exports = mount_getexports([strongSelf->_host UTF8String]);
        }

        if (!exports) {
            NSError *error = [NSError errorWithDomain:LNFSErrorDomain
                                                 code:-EIO
                                             userInfo:@{NSLocalizedDescriptionKey: @"Failed to list exports"}];
            [strongSelf finishWithExports:nil error:error completion:completion];
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

        [strongSelf finishWithExports:[result copy] error:nil completion:completion];
    });
}

#pragma mark - Directory operations

- (void)contentsOfDirectoryAtPath:(NSString *)path
                        recursive:(BOOL)recursive
                       completion:(void(^)(NSArray<LNFSFileItem *> *, NSError *))completion
{
    __weak typeof(self) weakSelf = self;
    dispatch_queue_t callbackQueue = _callbackQueue;

    dispatch_async(_queue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (completion) {
                dispatch_async(callbackQueue, ^{
                    completion(nil, [LNFSClient clientDeallocatedError]);
                });
            }
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];
        if (!ctx) {
            [strongSelf finishWithItems:nil
                                  error:[LNFSClient noContextError]
                             completion:completion];
            return;
        }

        NSError *error = nil;
        NSArray<LNFSFileItem *> *items = [ctx contentsOfDirectoryAtPath:path error:&error];
        if (!items) {
            [strongSelf finishWithItems:nil error:error completion:completion];
            return;
        }

        if (!recursive) {
            [strongSelf finishWithItems:items error:nil completion:completion];
            return;
        }

        NSMutableArray<LNFSFileItem *> *allItems = [NSMutableArray arrayWithArray:items];
        NSMutableSet<NSString *> *visitedPaths = [NSMutableSet set];
        if (path.length > 0) {
            [visitedPaths addObject:path];
        }

        BOOL success = [strongSelf recursivelyAddContents:items
                                              fromContext:ctx
                                                  toArray:allItems
                                             visitedPaths:visitedPaths
                                                    error:&error];

        [strongSelf finishWithItems:(success ? [allItems copy] : nil)
                              error:error
                         completion:completion];
    });
}

- (void)createDirectoryAtPath:(NSString *)path
                   completion:(void(^)(NSError *))completion
{
    __weak typeof(self) weakSelf = self;
    dispatch_queue_t callbackQueue = _callbackQueue;

    dispatch_async(_queue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (completion) {
                dispatch_async(callbackQueue, ^{
                    completion([LNFSClient clientDeallocatedError]);
                });
            }
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];
        if (!ctx) {
            [strongSelf finishWithError:[LNFSClient noContextError] completion:completion];
            return;
        }

        NSError *error = nil;
        [ctx mkdirAtPath:path error:&error];

        [strongSelf finishWithError:error completion:completion];
    });
}

- (void)removeDirectoryAtPath:(NSString *)path
                    recursive:(BOOL)recursive
                   completion:(void(^)(NSError *))completion
{
    __weak typeof(self) weakSelf = self;
    dispatch_queue_t callbackQueue = _callbackQueue;

    dispatch_async(_queue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (completion) {
                dispatch_async(callbackQueue, ^{
                    completion([LNFSClient clientDeallocatedError]);
                });
            }
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];
        if (!ctx) {
            [strongSelf finishWithError:[LNFSClient noContextError] completion:completion];
            return;
        }

        NSError *error = nil;
        if (recursive) {
            NSMutableSet<NSString *> *visitedPaths = [NSMutableSet set];
            [strongSelf recursivelyRemoveDirectoryAtPath:path
                                                 context:ctx
                                            visitedPaths:visitedPaths
                                                   error:&error];
        } else {
            [ctx rmdirAtPath:path error:&error];
        }

        [strongSelf finishWithError:error completion:completion];
    });
}

#pragma mark - File attributes

- (void)attributesOfItemAtPath:(NSString *)path
                    completion:(void(^)(LNFSFileItem *, NSError *))completion
{
    __weak typeof(self) weakSelf = self;
    dispatch_queue_t callbackQueue = _callbackQueue;

    dispatch_async(_queue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (completion) {
                dispatch_async(callbackQueue, ^{
                    completion(nil, [LNFSClient clientDeallocatedError]);
                });
            }
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];
        if (!ctx) {
            [strongSelf finishWithFileItem:nil
                                     error:[LNFSClient noContextError]
                                completion:completion];
            return;
        }

        NSError *error = nil;
        LNFSFileItem *item = [ctx statItemAtPath:path error:&error];

        [strongSelf finishWithFileItem:item error:error completion:completion];
    });
}

- (void)attributesOfFileSystemForPath:(NSString *)path
                           completion:(void(^)(NSDictionary<NSFileAttributeKey,id> *, NSError *))completion
{
    __weak typeof(self) weakSelf = self;
    dispatch_queue_t callbackQueue = _callbackQueue;

    dispatch_async(_queue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (completion) {
                dispatch_async(callbackQueue, ^{
                    completion(nil, [LNFSClient clientDeallocatedError]);
                });
            }
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];
        if (!ctx) {
            [strongSelf finishWithAttributes:nil
                                       error:[LNFSClient noContextError]
                                  completion:completion];
            return;
        }

        NSError *error = nil;
        NSDictionary *attrs = [ctx statvfs64AtPath:path error:&error];

        [strongSelf finishWithAttributes:attrs error:error completion:completion];
    });
}

- (void)destinationOfSymbolicLinkAtPath:(NSString *)path
                             completion:(void(^)(NSString *, NSError *))completion
{
    __weak typeof(self) weakSelf = self;
    dispatch_queue_t callbackQueue = _callbackQueue;

    dispatch_async(_queue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (completion) {
                dispatch_async(callbackQueue, ^{
                    completion(nil, [LNFSClient clientDeallocatedError]);
                });
            }
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];
        if (!ctx) {
            [strongSelf finishWithString:nil
                                   error:[LNFSClient noContextError]
                              completion:completion];
            return;
        }

        NSError *error = nil;
        NSString *dest = [ctx readlinkAtPath:path error:&error];

        [strongSelf finishWithString:dest error:error completion:completion];
    });
}

#pragma mark - File operations

- (void)removeFileAtPath:(NSString *)path
              completion:(void(^)(NSError *))completion
{
    __weak typeof(self) weakSelf = self;
    dispatch_queue_t callbackQueue = _callbackQueue;

    dispatch_async(_queue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (completion) {
                dispatch_async(callbackQueue, ^{
                    completion([LNFSClient clientDeallocatedError]);
                });
            }
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];
        if (!ctx) {
            [strongSelf finishWithError:[LNFSClient noContextError] completion:completion];
            return;
        }

        NSError *error = nil;
        [ctx unlinkAtPath:path error:&error];

        [strongSelf finishWithError:error completion:completion];
    });
}

- (void)removeItemAtPath:(NSString *)path
              completion:(void(^)(NSError *))completion
{
    __weak typeof(self) weakSelf = self;
    dispatch_queue_t callbackQueue = _callbackQueue;

    dispatch_async(_queue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (completion) {
                dispatch_async(callbackQueue, ^{
                    completion([LNFSClient clientDeallocatedError]);
                });
            }
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];
        if (!ctx) {
            [strongSelf finishWithError:[LNFSClient noContextError] completion:completion];
            return;
        }

        NSError *error = nil;
        LNFSFileItem *item = [ctx statItemAtPath:path error:&error];
        if (!item) {
            [strongSelf finishWithError:error completion:completion];
            return;
        }

        if (item.isDirectory) {
            NSMutableSet<NSString *> *visitedPaths = [NSMutableSet set];
            [strongSelf recursivelyRemoveDirectoryAtPath:path
                                                 context:ctx
                                            visitedPaths:visitedPaths
                                                   error:&error];
        } else {
            [ctx unlinkAtPath:path error:&error];
        }

        [strongSelf finishWithError:error completion:completion];
    });
}

- (void)moveItemAtPath:(NSString *)from
                toPath:(NSString *)to
            completion:(void(^)(NSError *))completion
{
    __weak typeof(self) weakSelf = self;
    dispatch_queue_t callbackQueue = _callbackQueue;

    dispatch_async(_queue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (completion) {
                dispatch_async(callbackQueue, ^{
                    completion([LNFSClient clientDeallocatedError]);
                });
            }
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];
        if (!ctx) {
            [strongSelf finishWithError:[LNFSClient noContextError] completion:completion];
            return;
        }

        NSError *error = nil;
        [ctx renameFrom:from to:to error:&error];

        [strongSelf finishWithError:error completion:completion];
    });
}

- (void)truncateFileAtPath:(NSString *)path
                  toOffset:(uint64_t)offset
                completion:(void(^)(NSError *))completion
{
    __weak typeof(self) weakSelf = self;
    dispatch_queue_t callbackQueue = _callbackQueue;

    dispatch_async(_queue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (completion) {
                dispatch_async(callbackQueue, ^{
                    completion([LNFSClient clientDeallocatedError]);
                });
            }
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];
        if (!ctx) {
            [strongSelf finishWithError:[LNFSClient noContextError] completion:completion];
            return;
        }

        NSError *error = nil;
        [ctx truncateAtPath:path offset:offset error:&error];

        [strongSelf finishWithError:error completion:completion];
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
    dispatch_queue_t callbackQueue = _callbackQueue;

    dispatch_async(_queue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (completion) {
                dispatch_async(callbackQueue, ^{
                    completion(nil, [LNFSClient clientDeallocatedError]);
                });
            }
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];
        if (!ctx) {
            [strongSelf finishWithData:nil
                                 error:[LNFSClient noContextError]
                            completion:completion];
            return;
        }

        NSError *error = nil;
        NSData *data = [ctx readFileAtPath:path
                                    offset:offset
                                    length:length
                                  progress:progress
                                     error:&error];

        [strongSelf finishWithData:data error:error completion:completion];
    });
}

- (void)writeData:(NSData *)data
           toPath:(NSString *)path
         progress:(BOOL(^ _Nullable)(int64_t))progress
       completion:(void(^)(NSError *))completion
{
    __weak typeof(self) weakSelf = self;
    dispatch_queue_t callbackQueue = _callbackQueue;

    dispatch_async(_queue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (completion) {
                dispatch_async(callbackQueue, ^{
                    completion([LNFSClient clientDeallocatedError]);
                });
            }
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];
        if (!ctx) {
            [strongSelf finishWithError:[LNFSClient noContextError] completion:completion];
            return;
        }

        NSError *error = nil;
        [ctx writeData:data toPath:path progress:progress error:&error];

        [strongSelf finishWithError:error completion:completion];
    });
}

- (void)uploadItemAtURL:(NSURL *)url
                 toPath:(NSString *)path
               progress:(BOOL(^ _Nullable)(int64_t))progress
             completion:(void(^)(NSError *))completion
{
    __weak typeof(self) weakSelf = self;
    dispatch_queue_t callbackQueue = _callbackQueue;

    dispatch_async(_queue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (completion) {
                dispatch_async(callbackQueue, ^{
                    completion([LNFSClient clientDeallocatedError]);
                });
            }
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];
        if (!ctx) {
            [strongSelf finishWithError:[LNFSClient noContextError] completion:completion];
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
            [strongSelf finishWithError:error completion:completion];
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
            [strongSelf finishWithError:error completion:completion];
            return;
        }

        uint64_t totalSize = [fileSizeValue unsignedLongLongValue];
        uint64_t totalUploaded = 0;
        uint64_t remoteOffset = 0;

        if (totalSize == 0) {
            NSError *truncateError = nil;
            BOOL truncated = [ctx truncateAtPath:path offset:0 error:&truncateError];
            if (!truncated && truncateError && truncateError.code != -ENOENT) {
                [fileHandle closeFile];
                [strongSelf finishWithError:truncateError completion:completion];
                return;
            }
            [fileHandle closeFile];
            [strongSelf finishWithError:nil completion:completion];
            return;
        }

        NSError *truncateError = nil;
        BOOL truncated = [ctx truncateAtPath:path offset:0 error:&truncateError];
        if (!truncated && truncateError && truncateError.code != -ENOENT) {
            [fileHandle closeFile];
            [strongSelf finishWithError:truncateError completion:completion];
            return;
        }

        while (totalUploaded < totalSize) {
            @autoreleasepool {
                NSUInteger bytesToRead = (NSUInteger)MIN((uint64_t)kLNFSClientLocalChunkSize,
                                                         totalSize - totalUploaded);
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
                totalUploaded = remoteOffset;

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
        [strongSelf finishWithError:error completion:completion];
    });
}

- (void)downloadItemAtPath:(NSString *)path
                     toURL:(NSURL *)url
                  progress:(BOOL(^ _Nullable)(int64_t, int64_t))progress
                completion:(void(^)(NSError *))completion
{
    __weak typeof(self) weakSelf = self;
    dispatch_queue_t callbackQueue = _callbackQueue;

    dispatch_async(_queue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (completion) {
                dispatch_async(callbackQueue, ^{
                    completion([LNFSClient clientDeallocatedError]);
                });
            }
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];
        if (!ctx) {
            [strongSelf finishWithError:[LNFSClient noContextError] completion:completion];
            return;
        }

        NSError *error = nil;
        [ctx readFileAtPath:path toFileURL:url progress:progress error:&error];

        [strongSelf finishWithError:error completion:completion];
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
                               code:-ECANCELED
                           userInfo:@{NSLocalizedDescriptionKey: @"Client was deallocated"}];
}

@end

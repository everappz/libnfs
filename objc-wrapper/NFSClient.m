/*
 Copyright (C) 2025 libnfs contributors

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU Lesser General Public License as published by
 the Free Software Foundation; either version 2.1 of the License, or
 (at your option) any later version.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU Lesser General Public License for more details.

 You should have received a copy of the GNU Lesser General Public License
 along with this program; if not, see <http://www.gnu.org/licenses/>.
 */

#import "NFSClient.h"
#import "NFSContext.h"
#include <nfsc/libnfs.h>
#include "libnfs-raw-mount.h"

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
    return [_context isConnected];
}

- (NSString *_Nullable)exportName {
    return _exportName;
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
    if ([_context isConnected]) {
        return _context;
    }
    return nil;
}

#pragma mark - Connection

- (void)connectToExport:(NSString *)exportName
             completion:(void(^)(NSError *))completion
{
    __weak typeof(self) weakSelf = self;
    dispatch_async(_queue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            completion([LNFSClient clientDeallocatedError]);
            return;
        }

        LNFSContext *ctx = [strongSelf createContext];

        NSError *error = nil;
        [ctx connectToServer:strongSelf->_host port:strongSelf->_port export:exportName error:&error];

        if ([ctx isConnected]) {
            strongSelf->_context = ctx;
            strongSelf->_exportName = [exportName copy];
        }

        completion(error);
    });
}

- (void)disconnectFromExportGracefully:(BOOL)gracefully
                            completion:(void(^)(NSError *))completion
{
    __weak typeof(self) weakSelf = self;
    dispatch_async(_queue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            completion(nil);
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];
        if (!ctx) {
            completion(nil);
            return;
        }

        NSError *error = nil;
        [ctx disconnectWithError:&error];

        strongSelf->_context = nil;
        strongSelf->_exportName = nil;

        completion(error);
    });
}

- (void)listExportsWithCompletion:(void(^)(NSArray<NSString *> *, NSError *))completion {
    __weak typeof(self) weakSelf = self;
    dispatch_async(_queue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            completion(nil, [LNFSClient clientDeallocatedError]);
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
            completion(nil, error);
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

        completion(result, nil);
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
            completion(nil, [LNFSClient clientDeallocatedError]);
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];
        if (!ctx) {
            completion(nil, [LNFSClient noContextError]);
            return;
        }

        NSError *error = nil;
        NSArray<LNFSFileItem *> *items = [ctx contentsOfDirectoryAtPath:path error:&error];
        if (!items) {
            completion(nil, error);
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
            completion(allItems, nil);
        } else {
            completion(items, nil);
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
            completion([LNFSClient clientDeallocatedError]);
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];
        if (!ctx) {
            completion([LNFSClient noContextError]);
            return;
        }

        NSError *error = nil;
        [ctx mkdirAtPath:path error:&error];

        completion(error);
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
            completion([LNFSClient clientDeallocatedError]);
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];
        if (!ctx) {
            completion([LNFSClient noContextError]);
            return;
        }

        NSError *error = nil;
        if (recursive) {
            [strongSelf recursivelyRemoveDirectoryAtPath:path context:ctx error:&error];
        } else {
            [ctx rmdirAtPath:path error:&error];
        }

        completion(error);
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
            completion(nil, [LNFSClient clientDeallocatedError]);
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];
        if (!ctx) {
            completion(nil, [LNFSClient noContextError]);
            return;
        }

        NSError *error = nil;
        LNFSFileItem *item = [ctx statItemAtPath:path error:&error];

        completion(item, error);
    });
}

- (void)attributesOfFileSystemForPath:(NSString *)path
                           completion:(void(^)(NSDictionary<NSFileAttributeKey,id> *, NSError *))completion
{
    __weak typeof(self) weakSelf = self;
    dispatch_async(_queue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            completion(nil, [LNFSClient clientDeallocatedError]);
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];
        if (!ctx) {
            completion(nil, [LNFSClient noContextError]);
            return;
        }

        NSError *error = nil;
        NSDictionary *attrs = [ctx statvfs64AtPath:path error:&error];

        completion(attrs, error);
    });
}

- (void)destinationOfSymbolicLinkAtPath:(NSString *)path
                             completion:(void(^)(NSString *, NSError *))completion
{
    __weak typeof(self) weakSelf = self;
    dispatch_async(_queue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            completion(nil, [LNFSClient clientDeallocatedError]);
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];
        if (!ctx) {
            completion(nil, [LNFSClient noContextError]);
            return;
        }

        NSError *error = nil;
        NSString *dest = [ctx readlinkAtPath:path error:&error];

        completion(dest, error);
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
            completion([LNFSClient clientDeallocatedError]);
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];
        if (!ctx) {
            completion([LNFSClient noContextError]);
            return;
        }

        NSError *error = nil;
        [ctx unlinkAtPath:path error:&error];

        completion(error);
    });
}

- (void)removeItemAtPath:(NSString *)path
              completion:(void(^)(NSError *))completion
{
    __weak typeof(self) weakSelf = self;
    dispatch_async(_queue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            completion([LNFSClient clientDeallocatedError]);
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];
        if (!ctx) {
            completion([LNFSClient noContextError]);
            return;
        }

        NSError *error = nil;
        LNFSFileItem *item = [ctx statItemAtPath:path error:&error];
        if (!item) {
            completion(error);
            return;
        }

        if (item.isDirectory) {
            [strongSelf recursivelyRemoveDirectoryAtPath:path context:ctx error:&error];
        } else {
            [ctx unlinkAtPath:path error:&error];
        }

        completion(error);
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
            completion([LNFSClient clientDeallocatedError]);
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];

        if (!ctx) {
            completion([LNFSClient noContextError]);
            return;
        }

        NSError *error = nil;
        [ctx renameFrom:from to:to error:&error];

        completion(error);
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
            completion([LNFSClient clientDeallocatedError]);
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];

        if (!ctx) {
            completion([LNFSClient noContextError]);
            return;
        }

        NSError *error = nil;
        [ctx truncateAtPath:path offset:offset error:&error];

        completion(error);
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
            completion(nil, [LNFSClient clientDeallocatedError]);
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];

        if (!ctx) {
            completion(nil, [LNFSClient noContextError]);
            return;
        }

        NSError *error = nil;
        NSData *data = [ctx readFileAtPath:path offset:offset length:length progress:progress error:&error];

        completion(data, error);
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
            completion([LNFSClient clientDeallocatedError]);
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];

        if (!ctx) {
            completion([LNFSClient noContextError]);
            return;
        }

        NSError *error = nil;
        [ctx writeData:data toPath:path progress:progress error:&error];

        completion(error);
    });
}

- (void)uploadItemAtURL:(NSURL *)url
                 toPath:(NSString *)path
               progress:(BOOL(^ _Nullable)(int64_t))progress
             completion:(void(^)(NSError *))completion
{
    __weak typeof(self) weakSelf = self;
    dispatch_async(_queue, ^{
        NSError *error = nil;
        NSData *data = [NSData dataWithContentsOfURL:url
                                             options:NSDataReadingMappedIfSafe
                                               error:&error];
        if (!data) {
            if (!error) {
                error = [NSError errorWithDomain:LNFSErrorDomain
                                            code:-EIO
                                        userInfo:@{NSLocalizedDescriptionKey: @"Failed to read local file"}];
            }
            completion(error);
            return;
        }

        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            completion([LNFSClient clientDeallocatedError]);
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];
        if (!ctx) {
            completion([LNFSClient noContextError]);
            return;
        }

        [ctx writeData:data toPath:path progress:progress error:&error];
        completion(error);
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
            completion([LNFSClient clientDeallocatedError]);
            return;
        }

        LNFSContext *ctx = [strongSelf connectedContext];

        if (!ctx) {
            completion([LNFSClient noContextError]);
            return;
        }

        NSError *error = nil;
        [ctx readFileAtPath:path toFileURL:url progress:progress error:&error];
        completion(error);
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

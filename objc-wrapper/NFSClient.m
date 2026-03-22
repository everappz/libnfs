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
    NSMutableDictionary<NSString *, LNFSContext *> *_contexts;
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
        _contexts = [[NSMutableDictionary alloc] init];
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

#pragma mark - Context management

- (LNFSContext *)contextForExport:(NSString *)exportName {
    LNFSContext *ctx = [_contexts objectForKey:exportName];
    if (!ctx) {
        ctx = [[LNFSContext alloc] init];
        ctx.timeout = self.timeout;
        ctx.uid = _uid;
        ctx.gid = _gid;
        [_contexts setObject:ctx forKey:exportName];
    }
    return ctx;
}

#pragma mark - Connection

- (void)connectToExport:(NSString *)exportName
             completion:(void(^)(NSError *))completion
{
    dispatch_async(_queue, ^{
        LNFSContext *ctx = [self contextForExport:exportName];
        NSError *error = nil;
        [ctx connectToServer:_host port:_port export:exportName error:&error];
        completion(error);
    });
}

- (void)disconnectFromExport:(NSString *)exportName
                  gracefully:(BOOL)gracefully
                  completion:(void(^)(NSError *))completion
{
    dispatch_async(_queue, ^{
        LNFSContext *ctx = [self contextForExport:exportName];
        if (!ctx) {
            completion(nil);
            return;
        }
        NSError *error = nil;
        [ctx disconnectWithError:&error];
        [_contexts removeObjectForKey:exportName];
        completion(error);
    });
}

- (void)listExportsWithCompletion:(void(^)(NSArray<NSString *> *, NSError *))completion {
    dispatch_async(_queue, ^{
        struct exportnode *exports;
        if (_port > 0) {
            exports = mount_getexports_mountport([_host UTF8String], _port);
        } else {
            exports = mount_getexports([_host UTF8String]);
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
                       exportName:(NSString *)exportName
                       completion:(void(^)(NSArray<LNFSFileItem *> *, NSError *))completion
{
    dispatch_async(_queue, ^{
        LNFSContext *ctx = [self contextForExport:exportName];
        if (!ctx) {
            completion(nil, [self noContextError]);
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
                        [self recursivelyAddContents:subItems
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
                   exportName:(NSString *)exportName
                   completion:(void(^)(NSError *))completion
{
    dispatch_async(_queue, ^{
        LNFSContext *ctx = [self contextForExport:exportName];
        if (!ctx) {
            completion([self noContextError]);
            return;
        }
        NSError *error = nil;
        [ctx mkdirAtPath:path error:&error];
        completion(error);
    });
}

- (void)removeDirectoryAtPath:(NSString *)path
                    recursive:(BOOL)recursive
                   exportName:(NSString *)exportName
                   completion:(void(^)(NSError *))completion
{
    dispatch_async(_queue, ^{
        LNFSContext *ctx = [self contextForExport:exportName];
        if (!ctx) {
            completion([self noContextError]);
            return;
        }

        NSError *error = nil;
        if (recursive) {
            [self recursivelyRemoveDirectoryAtPath:path context:ctx error:&error];
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
                    exportName:(NSString *)exportName
                    completion:(void(^)(LNFSFileItem *, NSError *))completion
{
    dispatch_async(_queue, ^{
        LNFSContext *ctx = [self contextForExport:exportName];
        if (!ctx) {
            completion(nil, [self noContextError]);
            return;
        }
        NSError *error = nil;
        LNFSFileItem *item = [ctx statItemAtPath:path error:&error];
        completion(item, error);
    });
}

- (void)attributesOfFileSystemForPath:(NSString *)path
                           exportName:(NSString *)exportName
                           completion:(void(^)(NSDictionary<NSFileAttributeKey,id> *, NSError *))completion
{
    dispatch_async(_queue, ^{
        LNFSContext *ctx = [self contextForExport:exportName];
        if (!ctx) {
            completion(nil, [self noContextError]);
            return;
        }
        NSError *error = nil;
        NSDictionary *attrs = [ctx statvfs64AtPath:path error:&error];
        completion(attrs, error);
    });
}

- (void)destinationOfSymbolicLinkAtPath:(NSString *)path
                             exportName:(NSString *)exportName
                             completion:(void(^)(NSString *, NSError *))completion
{
    dispatch_async(_queue, ^{
        LNFSContext *ctx = [self contextForExport:exportName];
        if (!ctx) {
            completion(nil, [self noContextError]);
            return;
        }
        NSError *error = nil;
        NSString *dest = [ctx readlinkAtPath:path error:&error];
        completion(dest, error);
    });
}

#pragma mark - File operations

- (void)removeFileAtPath:(NSString *)path
              exportName:(NSString *)exportName
              completion:(void(^)(NSError *))completion
{
    dispatch_async(_queue, ^{
        LNFSContext *ctx = [self contextForExport:exportName];
        if (!ctx) {
            completion([self noContextError]);
            return;
        }
        NSError *error = nil;
        [ctx unlinkAtPath:path error:&error];
        completion(error);
    });
}

- (void)removeItemAtPath:(NSString *)path
              exportName:(NSString *)exportName
              completion:(void(^)(NSError *))completion
{
    dispatch_async(_queue, ^{
        LNFSContext *ctx = [self contextForExport:exportName];
        if (!ctx) {
            completion([self noContextError]);
            return;
        }
        NSError *error = nil;
        LNFSFileItem *item = [ctx statItemAtPath:path error:&error];
        if (!item) {
            completion(error);
            return;
        }
        if (item.isDirectory) {
            [self recursivelyRemoveDirectoryAtPath:path context:ctx error:&error];
        } else {
            [ctx unlinkAtPath:path error:&error];
        }
        completion(error);
    });
}

- (void)moveItemAtPath:(NSString *)from
                toPath:(NSString *)to
            exportName:(NSString *)exportName
            completion:(void(^)(NSError *))completion
{
    dispatch_async(_queue, ^{
        LNFSContext *ctx = [self contextForExport:exportName];
        if (!ctx) {
            completion([self noContextError]);
            return;
        }
        NSError *error = nil;
        [ctx renameFrom:from to:to error:&error];
        completion(error);
    });
}

- (void)truncateFileAtPath:(NSString *)path
                  toOffset:(uint64_t)offset
                exportName:(NSString *)exportName
                completion:(void(^)(NSError *))completion
{
    dispatch_async(_queue, ^{
        LNFSContext *ctx = [self contextForExport:exportName];
        if (!ctx) {
            completion([self noContextError]);
            return;
        }
        NSError *error = nil;
        [ctx truncateAtPath:path offset:offset error:&error];
        completion(error);
    });
}

#pragma mark - Read / Write

- (void)contentsAtPath:(NSString *)path
            exportName:(NSString *)exportName
              progress:(BOOL(^ _Nullable)(int64_t, int64_t))progress
            completion:(void(^)(NSData *, NSError *))completion
{
    [self contentsAtPath:path offset:0 length:0 exportName:exportName progress:progress completion:completion];
}

- (void)contentsAtPath:(NSString *)path
                offset:(int64_t)offset
                length:(int64_t)length
            exportName:(NSString *)exportName
              progress:(BOOL(^ _Nullable)(int64_t, int64_t))progress
            completion:(void(^)(NSData *, NSError *))completion
{
    dispatch_async(_queue, ^{
        LNFSContext *ctx = [self contextForExport:exportName];
        if (!ctx) {
            completion(nil, [self noContextError]);
            return;
        }
        NSError *error = nil;
        NSData *data = [ctx readFileAtPath:path offset:offset length:length progress:progress error:&error];
        completion(data, error);
    });
}

- (void)writeData:(NSData *)data
           toPath:(NSString *)path
       exportName:(NSString *)exportName
         progress:(BOOL(^ _Nullable)(int64_t))progress
       completion:(void(^)(NSError *))completion
{
    dispatch_async(_queue, ^{
        LNFSContext *ctx = [self contextForExport:exportName];
        if (!ctx) {
            completion([self noContextError]);
            return;
        }
        NSError *error = nil;
        [ctx writeData:data toPath:path progress:progress error:&error];
        completion(error);
    });
}

- (void)uploadItemAtURL:(NSURL *)url
                 toPath:(NSString *)path
             exportName:(NSString *)exportName
               progress:(BOOL(^ _Nullable)(int64_t))progress
             completion:(void(^)(NSError *))completion
{
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

        LNFSContext *ctx = [self contextForExport:exportName];
        if (!ctx) {
            completion([self noContextError]);
            return;
        }

        [ctx writeData:data toPath:path progress:progress error:&error];
        completion(error);
    });
}

- (void)downloadItemAtPath:(NSString *)path
                     toURL:(NSURL *)url
                exportName:(NSString *)exportName
                  progress:(BOOL(^ _Nullable)(int64_t, int64_t))progress
                completion:(void(^)(NSError *))completion
{
    dispatch_async(_queue, ^{
        LNFSContext *ctx = [self contextForExport:exportName];
        if (!ctx) {
            completion([self noContextError]);
            return;
        }

        NSError *error = nil;
        [ctx readFileAtPath:path toFileURL:url progress:progress error:&error];
        completion(error);
    });
}

#pragma mark - Helpers

- (NSError *)noContextError {
    return [NSError errorWithDomain:LNFSErrorDomain
                               code:-ENOTCONN
                           userInfo:@{NSLocalizedDescriptionKey: @"Not connected to any export"}];
}

@end

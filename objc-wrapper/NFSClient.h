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

#import <Foundation/Foundation.h>
#import "NFSFileItem.h"

NS_ASSUME_NONNULL_BEGIN

@interface LNFSClient : NSObject

- (instancetype)initWithHost:(NSString *)host port:(int)port;

@property (nonatomic) NSTimeInterval timeout;
@property (nonatomic) int32_t uid;
@property (nonatomic) int32_t gid;

#pragma mark - Connection

- (BOOL)isConnected;

- (NSString *_Nullable)exportName;

- (void)connectToExport:(NSString *)exportName
             completion:(void(^)(NSError *))completion;

- (void)disconnectFromExportGracefully:(BOOL)gracefully
                            completion:(void(^)(NSError * _Nullable error))completion;

- (void)listExportsWithCompletion:(void(^)(NSArray<NSString *> * _Nullable exports,
                                           NSError * _Nullable error))completion;

#pragma mark - Directory operations

- (void)contentsOfDirectoryAtPath:(NSString *)path
                        recursive:(BOOL)recursive
                       completion:(void(^)(NSArray<LNFSFileItem *> *, NSError *))completion;

- (void)createDirectoryAtPath:(NSString *)path
                   completion:(void(^)(NSError *))completion;

- (void)removeDirectoryAtPath:(NSString *)path
                    recursive:(BOOL)recursive
                   completion:(void(^)(NSError * _Nullable error))completion;

#pragma mark - File attributes

- (void)attributesOfItemAtPath:(NSString *)path
                    completion:(void(^)(LNFSFileItem * _Nullable item,
                                        NSError * _Nullable error))completion;

- (void)attributesOfFileSystemForPath:(NSString *)path
                           completion:(void(^)(NSDictionary<NSFileAttributeKey, id> * _Nullable attrs,
                                               NSError * _Nullable error))completion;

- (void)destinationOfSymbolicLinkAtPath:(NSString *)path
                             completion:(void(^)(NSString * _Nullable destination,
                                                 NSError * _Nullable error))completion;

#pragma mark - File operations

- (void)removeFileAtPath:(NSString *)path
              completion:(void(^)(NSError * _Nullable error))completion;

- (void)removeItemAtPath:(NSString *)path
              completion:(void(^)(NSError * _Nullable error))completion;

- (void)moveItemAtPath:(NSString *)from
                toPath:(NSString *)to
            completion:(void(^)(NSError * _Nullable error))completion;

- (void)truncateFileAtPath:(NSString *)path
                  toOffset:(uint64_t)offset
                completion:(void(^)(NSError * _Nullable error))completion;

#pragma mark - Read / Write

- (void)contentsAtPath:(NSString *)path
              progress:(BOOL(^ _Nullable)(int64_t bytes, int64_t total))progress
            completion:(void(^)(NSData * _Nullable data,
                                NSError * _Nullable error))completion;

- (void)contentsAtPath:(NSString *)path
                offset:(int64_t)offset
                length:(int64_t)length
              progress:(BOOL(^ _Nullable)(int64_t bytes, int64_t total))progress
            completion:(void(^)(NSData * _Nullable data,
                                NSError * _Nullable error))completion;

- (void)writeData:(NSData *)data
           toPath:(NSString *)path
         progress:(BOOL(^ _Nullable)(int64_t bytes))progress
       completion:(void(^)(NSError * _Nullable error))completion;

- (void)uploadItemAtURL:(NSURL *)url
                 toPath:(NSString *)path
               progress:(BOOL(^ _Nullable)(int64_t bytes))progress
             completion:(void(^)(NSError * _Nullable error))completion;

- (void)downloadItemAtPath:(NSString *)path
                     toURL:(NSURL *)url
                  progress:(BOOL(^ _Nullable)(int64_t bytes, int64_t total))progress
                completion:(void(^)(NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END

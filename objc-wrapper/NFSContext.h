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

FOUNDATION_EXTERN NSString *const LNFSErrorDomain;

@interface LNFSContext : NSObject

@property (nonatomic) NSTimeInterval timeout;
@property (nonatomic) int32_t uid;
@property (nonatomic) int32_t gid;

- (BOOL)isConnected;

// Connection
- (BOOL)connectToServer:(NSString *)server
                 export:(NSString *)exportName
                  error:(NSError **)error;
- (BOOL)disconnectWithError:(NSError **)error;

// Stat
- (nullable LNFSFileItem *)statItemAtPath:(NSString *)path
                                    error:(NSError **)error;

// Statvfs
- (nullable NSDictionary<NSFileAttributeKey, id> *)statvfs64AtPath:(NSString *)path
                                                             error:(NSError **)error;

// Directory operations
- (BOOL)mkdirAtPath:(NSString *)path error:(NSError **)error;
- (BOOL)rmdirAtPath:(NSString *)path error:(NSError **)error;
- (nullable NSArray<LNFSFileItem *> *)contentsOfDirectoryAtPath:(NSString *)path
                                                          error:(NSError **)error;

// File operations
- (BOOL)unlinkAtPath:(NSString *)path error:(NSError **)error;
- (BOOL)renameFrom:(NSString *)oldPath to:(NSString *)newPath error:(NSError **)error;
- (BOOL)truncateAtPath:(NSString *)path offset:(uint64_t)offset error:(NSError **)error;
- (nullable NSString *)readlinkAtPath:(NSString *)path error:(NSError **)error;

// File I/O
- (nullable NSData *)readFileAtPath:(NSString *)path
                             offset:(int64_t)offset
                             length:(int64_t)length
                           progress:(BOOL(^ _Nullable)(int64_t bytes, int64_t total))progress
                              error:(NSError **)error;

- (BOOL)writeData:(NSData *)data
           toPath:(NSString *)path
         progress:(BOOL(^ _Nullable)(int64_t bytes))progress
            error:(NSError **)error;

// Streaming file I/O (avoids loading entire file into memory)
- (BOOL)readFileAtPath:(NSString *)path
             toFileURL:(NSURL *)localURL
              progress:(BOOL(^ _Nullable)(int64_t bytes, int64_t total))progress
                 error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

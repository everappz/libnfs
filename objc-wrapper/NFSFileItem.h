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

NS_ASSUME_NONNULL_BEGIN

@interface LNFSFileItem : NSObject

@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSString *path;
@property (nonatomic, readonly) BOOL isDirectory;
@property (nonatomic, readonly) BOOL isRegularFile;
@property (nonatomic, readonly) BOOL isSymbolicLink;
@property (nonatomic, readonly) int64_t fileSize;
@property (nonatomic, readonly, copy) NSDate *modificationDate;
@property (nonatomic, readonly, copy) NSDate *accessDate;
@property (nonatomic, readonly, copy) NSDate *creationDate;
@property (nonatomic, readonly) uint64_t inode;
@property (nonatomic, readonly) uint32_t nlink;
@property (nonatomic, readonly) uint32_t mode;

@end

NS_ASSUME_NONNULL_END

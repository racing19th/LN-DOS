#include <fs/fs.h>
#include <fs/devfile.h>
#include <mm/memset.h>
#include <mm/paging.h>
#include <mm/heap.h>
#include <sched/spinlock.h>
#include <errno.h>
#include <sched/thread.h> //for jiffyCounter
#include <print.h>
#include <panic.h>
#include <userspace.h>

struct CfEntry { //describes 1 page of file data
	void *addr;
	uint64_t fileOffset;
	bool dirty;
	uint32_t lastAccessed;
};

struct CachedFile {
	unsigned int nrofEntries;
	struct CfEntry entries[1];
};

int fsTruncate(struct File *file, uint64_t newSize) {
	int error = 0;
	acquireSpinlock(&file->lock);
	struct Inode *inode = file->inode;
	acquireSpinlock(&inode->lock);

	if ((inode->type & ITYPE_MASK) != ITYPE_FILE) {
		error = -EISDIR;
		goto ret;
	}

	if (newSize > inode->fileSize) {
		error = -ENOSYS;
		goto ret;
	}
	struct CachedFile *cf = inode->cachedData;
	if (!cf) {
		goto ret; //error = 0;
	}

	int nrofEntries = cf->nrofEntries;
	for (unsigned int i = 0; i < cf->nrofEntries; i++) {
		if (cf->entries[i].fileOffset < newSize) {
			continue;
		}
		nrofEntries--;
		deallocPages(cf->entries[i].addr, PAGE_SIZE);
		cf->entries[i].addr = NULL;
	}
	if (nrofEntries) {
		struct CachedFile *newCF = kmalloc(sizeof(*newCF) + (nrofEntries - 1));
		newCF->nrofEntries = nrofEntries;
		unsigned int oldIndex = 0;
		for (int i = 0; i < nrofEntries; i++) {
			struct CfEntry *oldEntry = NULL;
			for (; oldIndex < cf->nrofEntries; oldIndex++) {
				if (cf->entries[i].addr) {
					oldEntry = &cf->entries[i];
					oldIndex++;
					break;
				}
			}
			if (!oldEntry) {
				panic("fsTruncate: unexpected nrof cf entries\n");
			}
			memcpy(&newCF->entries[i], oldEntry, sizeof(struct CfEntry));
		}
		inode->cachedData = newCF;
		
	} else {
		inode->cachedData = NULL;
	}
	kfree(cf);

	//releaseInode:
	ret:
	releaseSpinlock(&inode->lock);
	releaseSpinlock(&file->lock);
	return error;
}

ssize_t fsRead(struct File *file, void *buffer, size_t bufSize) {
	acquireSpinlock(&file->lock);
	struct Inode *inode = file->inode;
	acquireSpinlock(&inode->lock);

	ssize_t bytesCopied = 0;
	if (isDir(inode)) {
		bytesCopied = -EISDIR;
		goto ret;
	}
	if (!inode->cachedData) {
		goto ret; //bytesCopied = 0
	}

	if ((inode->type & ITYPE_MASK) == ITYPE_CHAR) {
		bytesCopied = -ENOSYS;
		struct DevFileOps *ops = inode->ops;
		if (ops && ops->read) {
			bytesCopied = ops->read(file, buffer, bufSize);
		}
		goto ret;
	}

	size_t bytesLeft = inode->fileSize - file->offset;
	if (bytesLeft > bufSize) {
		bytesLeft = bufSize;
	}
	
	if (inode->ramfs & RAMFS_INITRD) {
		//memcpy(buffer, inode->cachedData + file->offset, bytesLeft);
		int error = userMemcpy(buffer, inode->cachedData + file->offset, bytesLeft);
		if (!error) {
			bytesCopied = bytesLeft;
			file->offset += bytesLeft;
		} else {
			bytesCopied = error;
		}
		
		goto ret;
	}

	struct CachedFile *cf = inode->cachedData;
	uint64_t oldOffset = file->offset;

	while (bytesLeft) {
		struct CfEntry *entry = NULL;
		uint64_t offset;
		for (unsigned int i = 0; i < cf->nrofEntries; i++) {
			offset = cf->entries[i].fileOffset;
			if (file->offset >= offset && file->offset < offset + PAGE_SIZE) {
				entry = &cf->entries[i];
				break;
			}
		}
		if (!entry) {
			//load entry from fs, reacquire spinlocks and reload cf
			printk("Error reading file: unimplemented");
			bytesCopied = -ENOSYS;
			goto ret;
			//continue;
		}
		entry->lastAccessed = jiffyCounter;
		unsigned int diff = file->offset - offset;
		//unsigned int nrofBytes = PAGE_SIZE - diff;
		unsigned int nrofBytes = ((bytesLeft > PAGE_SIZE)? PAGE_SIZE : bytesLeft);
		//memcpy(buffer, (void *)((uintptr_t)(entry->addr) + diff), nrofBytes);
		int error = userMemcpy(buffer, (void *)((uintptr_t)(entry->addr) + diff), nrofBytes);
		if (error) {
			file->offset = oldOffset;
			bytesCopied = error;
			goto ret;
		}

		buffer = (void *)((uintptr_t)buffer + nrofBytes);
		file->offset += nrofBytes;
		bytesLeft -= nrofBytes;
		bytesCopied += nrofBytes;
	}

	ret:
	releaseSpinlock(&inode->lock);
	releaseSpinlock(&file->lock);
	return bytesCopied;
}

int fsWrite(struct File *file, const void *buffer, size_t bufSize) {
	acquireSpinlock(&file->lock);
	struct Inode *inode = file->inode;
	

	int error = 0;
	if (isDir(inode)) {
		error = -EISDIR;
		goto releaseFileLock;
	}

	if ((inode->type & ITYPE_MASK) == ITYPE_CHAR) {
		error = -ENOSYS;
		struct DevFileOps *ops = inode->ops;
		if (ops && ops->write) {
			error = ops->write(file, buffer, bufSize);
		}
		goto releaseFileLock;
	}

	if (inode->ramfs & RAMFS_INITRD) {
		error = -EROFS;
		goto releaseFileLock;
	}

	acquireSpinlock(&inode->lock);
	struct CachedFile *cf = inode->cachedData;
	
	while (bufSize) {
		inode->cacheDirty = true;
		if (file->offset == inode->fileSize && !(inode->fileSize % PAGE_SIZE)) { //offset can never be greater
			unsigned int nrofPages = sizeToPages(bufSize);
			
			size_t newCFSize;
			if (file->offset) {
				//create new cf entries
				newCFSize = inode->cachedDataSize + (sizeof(struct CfEntry) * nrofPages);
				struct CachedFile *newCF = krealloc(cf, newCFSize);
				if (!newCF) {
					error = -ENOMEM;
					goto ret;
				}
				cf = newCF;
			} else {
				//create new cf
				newCFSize = sizeof(struct CachedFile) + (nrofPages - 1) * sizeof(struct CfEntry);
				cf = kmalloc(newCFSize);
				if (!cf) {
					error = -ENOMEM;
					goto ret;
				}
				cf->nrofEntries = 0;
			}
			inode->cachedDataSize = newCFSize;
			inode->cachedData = cf;

			for (unsigned int i = 0; i < nrofPages; i++) {
				//alloc page
				void *page = allocKPages(PAGE_SIZE, PAGE_FLAG_WRITE);
				if (!page) {
					error = -ENOMEM;
					goto ret;
				}

				//map it in the entry
				cf->entries[cf->nrofEntries].addr = page;
				cf->entries[cf->nrofEntries].fileOffset = file->offset + i * PAGE_SIZE;
				cf->entries[cf->nrofEntries].dirty = true;
				cf->entries[cf->nrofEntries].lastAccessed = jiffyCounter;

				cf->nrofEntries += 1;

				//and write
				unsigned int copy = (bufSize > PAGE_SIZE)? PAGE_SIZE : bufSize;
				//memcpy(page, buffer, copy);
				error = userMemcpy(page, buffer, copy);
				if (error) {
					goto ret;
				}
				buffer = (void *)((uintptr_t)buffer + copy);
				bufSize -= copy;
				file->offset += copy;
				inode->fileSize += copy;
			}
			
			break; //bufsize should be zero
		}

		//find entry
		struct CfEntry *entry = NULL;
		uint64_t offset;
		for (unsigned int i = 0; i < cf->nrofEntries; i++) {
			offset = cf->entries[i].fileOffset;
			if (file->offset >= offset && file->offset < offset + PAGE_SIZE) {
				entry = &cf->entries[i];
				break;
			}
		}
		if (!entry) {
			//load entry from fs, reacquire spinlocks and reload cf
			printk("Error reading file: unimplemented");
			error = -ENOSYS;
			goto ret;
			//continue;
		}
		entry->lastAccessed = jiffyCounter;
		entry->dirty = true;

		unsigned int diff = file->offset - offset;
		unsigned int nrofBytes = PAGE_SIZE - diff;
		//memcpy((void *)((uintptr_t)(entry->addr) + diff), buffer, nrofBytes);
		error = userMemcpy((void *)((uintptr_t)(entry->addr) + diff), buffer, nrofBytes);
		if (error) {
			goto ret;
		}

		buffer = (void *)((uintptr_t)buffer + nrofBytes);
		file->offset += nrofBytes;
		bufSize -= nrofBytes;
		if (file->offset > inode->fileSize) {
			inode->fileSize = file->offset;
		}
	}

	ret:
	releaseSpinlock(&inode->lock);
	releaseFileLock:
	releaseSpinlock(&file->lock);
	return error;
}

int fsSeek(struct File *file, int64_t offset, int whence) {
	acquireSpinlock(&file->lock);
	acquireSpinlock(&file->inode->lock);

	int64_t newOffset;
	int error = 0;
	switch (whence) {
		case SEEK_SET:
			if (offset < 0 || offset > (int64_t)file->inode->fileSize) {
				error = -EINVAL;
				break;
			}
			file->offset = offset;
			break;
		case SEEK_CUR:
			newOffset = file->offset + offset;
			if (newOffset < 0 || newOffset > (int64_t)file->inode->fileSize) {
				error = -EINVAL;
				break;
			} 
			file->offset = newOffset;
			break;
		case SEEK_END:
			newOffset = file->inode->fileSize + offset;
			if (newOffset < 0 || newOffset > (int64_t)file->inode->fileSize) {
				error = -EINVAL;
				break;
			} 
			file->offset = newOffset;
			break;
		default:
			error = -EINVAL;
			break;
	}

	releaseSpinlock(&file->inode->lock);
	releaseSpinlock(&file->lock);
	return error;
}

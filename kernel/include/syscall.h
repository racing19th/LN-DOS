#ifndef INCLUDE_SYSCALL_H
#define INCLUDE_SYSCALL_H

#include <stdint.h>
#include <stddef.h>
#include <errno.h>

/*
#define DEFINE_SYSCALL(func) \
	static int (*syscall_##func)(...) __attribute__((used, section (".syscalls"))) = func
*/

static inline int validateUserPointer(void *ptr, size_t size) {
	uintptr_t uptr = (uintptr_t)ptr;
	if (uptr & 0xFFFF8000UL << 32 || (0xFFFF8000UL << 32) - uptr < size) {
		return -EINVAL;
	}
	return 0;
}

static inline int validateUserString(const char *str) {
	while (true) {
		if ((uintptr_t)str & 0xFFFF8000UL << 32) {
			return -EINVAL;
		}
		if (!*str) {
			return 0;
		}
		str++;
	}
}

void registerSyscall(int nr, int (*func)());

#endif
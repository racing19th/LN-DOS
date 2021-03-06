#include <string.h>
#include <stdbool.h>

void *memcpy(void *dest, const void *src, size_t n) {
	if (n % sizeof(long)) {
		const char *csrc = (const char *)src;
		char *cdest = (char *)dest;
		for (size_t i = 0; i < n; i++) {
			cdest[i] = csrc[i];
		}
	} else {
		const long *lsrc = (const long *)src;
		long *ldest = (long *)dest;
		for (size_t i = 0; i < n / 8; i++) {
			ldest[i] = lsrc[i];
		}
	}
	return dest;
}

void *memset(void *str, int c, size_t n) {
	char *cstr = (char *)str;
	for (size_t i = 0; i < n; i++) {
		cstr[i] = c;
	}
	return str;
}

int memcmp(const void *a, const void *b, size_t n) {
	int ret = 0;
	for (size_t i = 0; i < n; i++) {
		ret = ((char*)a)[i] - ((char*)b)[i];
		if (ret) break;
	}
	return ret;
}

void *memchr(const void *s, int c, size_t n) {
	const char *s2 = s;
	for (size_t i = 0; i < n; i++) {
		if (s2[i] == c) {
			return (void *)&s2[i];
		}
	}
	return NULL;
}

size_t strlen(const char *str) {
	size_t ret = 0;
	while (*str) {
		ret++;
		str++;
	}
	return ret;
}

char *strcpy(char *dest, const char *src) {
	char *oldDest = dest;
	while ((*dest = *src) != 0) {
		src++;
		dest++;
	}
	return oldDest;
}

const char *strchr(const char *s, int c) {
	while (*s) {
		if (*s == c) {
			return s;
		}
		s++;
	}
	return NULL;
}

const char *strchrnul(const char *s, int c) {
	while (*s) {
		if (*s == c) {
			return s;
		}
		s++;
	}
	return s;
}

int strcmp(const char *s1, const char *s2) {
	int len = strlen(s1) + 1;
	return memcmp(s1, s2, len);
}

char *strpbrk(const char *s, const char *accept) {
	while (*s) {
		const char *a = accept;
		while (*a) {
			if (*s == *a) {
				return (char *)s;
			}
			a++;
		}
		s++;
	}
	return NULL;
}

size_t strspn(const char *s, const char *accept) {
	size_t ret = 0;
	while (s[ret]) {
		bool found = false;
		const char *a = accept;
		while (*a) {
			if (s[ret] == *a) {
				found = true;
				break;
			}
			a++;
		}
		if (!found) {
			break;
		}
	}
	return ret;
}

char *strstr(const char *str, const char *substr) {
	int pos = 0;
	size_t len = strlen(substr);
	while (str[pos]) {
		if (!memcmp(str, substr, len)) {
			return (char *)&str[pos];
		}
		pos++;
	}
	return NULL;
}
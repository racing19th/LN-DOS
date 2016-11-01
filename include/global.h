#ifndef INCLUDE_GLOBAL_H
#define INCLUDE_GLOBAL_H

#define PTRSIZE 4
#define PAGESIZE 4096

#define NULL 0


//signed integer types
typedef signed char int8_t;
typedef signed short int16_t;
typedef signed long int32_t;
typedef signed long long int64_t;
//unsigned integer types
typedef unsigned char uint8_t;
typedef unsigned short uint16_t;
typedef unsigned long uint32_t;
typedef unsigned long long uint64_t;

typedef uint32_t uintptr_t;

typedef uint32_t size_t;

typedef enum {false, true} bool;

#endif

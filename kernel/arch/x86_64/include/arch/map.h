#ifndef MAP_H
#define MAP_H

#include <stdint.h>
#include <stdbool.h>
#include <mm/paging.h>

#define NROF_PAGE_LEVELS	4
#define PAGE_MASK			0x0000FFFFFFFFF000

typedef uint64_t pte_t;

extern bool nxEnabled;

/*
Finds the entry in the page table at a specified level and sets it to a specified value.
*/
void mmSetPageEntry(uintptr_t addr, uint8_t level, pte_t entry);

/*
Finds the entry in the page table at a specified level and returns it.
*/
pte_t *mmGetEntry(uintptr_t addr, uint8_t level);

/*
Get the virtual address that is mapped by a specified pte_t pointer
*/
uintptr_t getAddrFromPte(pte_t *pte, uint8_t level);

void mmUnmapBootPages(void);

#endif

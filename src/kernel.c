#include "io.h"
#include "video.h"
#include "kernel.h"
#include "memory.h"
#include "param.h"
#include "irq.h"
#include "tty.h"


void kmain(void) {
	init_memory();
	video_init();
	irq_init();
	linewidth = get_line_width();
	screenheight = vga_get_vertchars();
	cursorX = partable->cursorX;
	cursorY = partable->cursorY;
	tty_set_full_screen_attrib(0x07);
	sprint("Kernel initialising...\n", currentattrib);
	//tty_clear_screen();
	crashtest();
	while (1) {};
}


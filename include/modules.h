#ifndef INCLUDE_MODULES_H
#define INCLUDE_MODULES_H

#define NROF_MODULE_INIT_LEVELS		4

typedef int(*moduleCall_t)(void);

#define MODULE_INIT_LEVEL(func, lv)	\
	static moduleCall_t __moduleInit_##func __attribute__((used, section (".moduleInits" #lv ))) = func

#define MODULE_INIT(func)	MODULE_INIT_LEVEL(func, 2)

#endif
#include <stdint.h>
#include <stddef.h>
#include <spinlock.h>
#include "queue.h"
#include <sched/thread.h>

struct threadInfoQueue {
	struct threadInfo *first;
	struct threadInfo *last;
	int nrofThreads;
	spinlock_t lock;
};

struct threadInfoQueue queue;

struct threadInfo *pullThread(void) {
	acquireSpinlock(&(queue.lock));
	struct threadInfo *ret = queue.first;
	if (!ret) {
		releaseSpinlock(&(queue.lock));
		return NULL;
	}
	if (queue.last == queue.first) {
		queue.last = NULL;
	}
	queue.first = ret->nextThread;
	queue.nrofThreads -= 1;
	releaseSpinlock(&(queue.lock));
	return ret;
}

void pushThread(struct threadInfo *thread) {
	if (!thread) {
		return;
	}
	thread->nextThread = NULL;
	acquireSpinlock(&(queue.lock));
	if (queue.last) {
		queue.last->nextThread = thread;
		queue.last = thread;
	} else {
		queue.first = thread;
		queue.last = thread;
	}
	queue.nrofThreads += 1;
	releaseSpinlock(&(queue.lock));
}

void pushThreadFront(struct threadInfo *thread) {
	if (!thread) {
		return;
	}
	thread->nextThread = NULL;
	acquireSpinlock(&(queue.lock));
	thread->nextThread = queue.first;
	queue.first = thread;
	if (!queue.last) {
		queue.last = thread;
	}
	queue.nrofThreads += 1;
	releaseSpinlock(&(queue.lock));
}
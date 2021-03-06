extern ackIRQ
extern initStackEnd
extern acquireSpinlock
extern releaseSpinlock
extern getCurrentThread
extern setCurrentThread
extern kthreadSwitch
extern kthreadFreeJoined
extern readyQueuePop
extern sleepSkipTime
extern deallocThread
extern loadThread

extern perCpuTimer
extern initProcess
extern lapicSendIPIToAll
extern tssSetRSP0
extern handleSignal

global kthreadExit:function
global kthreadInit:function
global jiffyIrq:function
global reschedIPI:function
global migrateMainStack:function
global kthreadStop:function

global uthreadInit:function

global jiffyCounter:data

global nextThread:function

SECTION .text

;thread stack layout:
;init | resume | register
;-08	 XX		return to exit
;Saved by interrupt handler
;-10	+98		ss
;-18	+90		rsp
;-20	+88		rflags
;-28	+80		cs
;-30	+78		rip
;Mandatory saved registers
;-38	+70		rax
;-40	+68		rcx
;-48	+60		rdx
;-50	+58		rdi
;-58	+50		rsi
;-60	+48		r8
;-68	+40		r9
;-70	+38		r10
;-78	+30		r11
;Optionally saved registers (only on task switch)
;-80	+28		rbx
;-88	+20		rbp
;-90	+18		r12
;-98	+10		r13
;-A0	+08		r14
;-A8	rsp		r15

kthreadInit:
	pushfq
	
	mov [rdi - 0x30], rsi	;Point rip to function start
	mov [rdi - 0x50], rdx	;Put arg in rdi
	mov rax, kthreadReturn
	mov [rdi - 0x08], rax	;Put return address on stack
	mov rax, rdi
	sub rax, 0x08
	mov [rdi - 0x18], rax	;Set rsp
	sub rax, 0xA0
	mov [rdi], rax			;Set stack pointer in threadInfo

	pop rcx

	mov eax, 0x10			;data segment
	mov edx, 0x08			;code segment
	mov [rdi - 0x10], rax	;Set ss
	mov [rdi - 0x28], rdx	;Set cs

	mov [rdi - 0x20], rcx
	ret

uthreadInit: ;(struct ThreadInfo *info (rdi), func *start(rsi), uint64_t arg1 (rdx), uint64_t arg2 (rcx), uint64_t userspaceStackpointer (r8))
	pushfq
	pop rax
	
	mov qword [rdi - 0x08], qword 0x23 ;ss
	mov [rdi - 0x10], r8 ;rsp
	mov [rdi - 0x18], rax ;rflags
	mov qword [rdi - 0x20], qword 0x2B ;cs = 64-bit usermode text
	mov [rdi - 0x28], rsi ;rip

	mov [rdi - 0x48], rdx
	mov [rdi - 0x50], rcx

	;set stackpointer in ThreadInfo to kernel stack
	lea rax, [rdi - 0xA0]
	mov [rdi], rax

	ret

kthreadReturn:
	mov rdi, rax
kthreadExit:
	mov r14, rdi ;r14 = thread return value
	call getCurrentThread
	mov r15, rax
	lea rdi, [rax + 0x14]
	call acquireSpinlock

	mov [r15 + 8], r14 ;set return value
	mov [r15 + 0x10], dword 0 ;set threadstate to FINISHED

	;switch to exception stack
	mov rsp, [gs:0x10]
	mov rbp, [gs:0x10]
	;set current thread to NULL
	xor edi, edi
	call setCurrentThread

	mov eax, [r15 + 0x18]
	mov r13d, 1
	test eax, eax
	jnz nextThread ;don't free joined if thread is detached
		mov rdi, r15
		call kthreadFreeJoined

		;switch to exception stack
		;mov rsp, [gs:0x10]
		;mov rbp, [gs:0x10]

		and [r15 + 0x14], dword ~2
		lea rdi, [r15 + 0x14]
		call releaseSpinlock

		xor r13d, r13d
		;xor edi, edi
		;call setCurrentThread
		jmp nextThread
	
reschedCommon:
	pop rcx

	push rbx
	push rbp
	push r12
	push r13
	push r14
	push r15

	push rcx ;ret addr
	;get current thread
	mov rax, [gs:8]
	push rax
	push rdx
	
	lea rdi, [rax + 0x14]
	call acquireSpinlock

	;mov esi, 1
	mov rdi, [gs:8]
	pop rdx
	lea rcx, [rsp + 0x10] ;irqStack
	call kthreadSwitch

	pop rdx
	cmp rax, rdx
	je .noSwitch
		;task switch occured
		pop rcx ;save ret addr in rcx
		;save rsp
		mov [rdx], rsp
		;get new rsp
		mov rsp, [rax]
		;restore optional registers
		mov rbx, [rsp + 0x28]
		mov rbp, [rsp + 0x20]
		mov r12, [rsp + 0x18]
		mov r13, [rsp + 0x10]
		mov r14, [rsp + 0x08]
		mov r15, [rsp]
		add rsp, 0x30
		
		push rcx ;save ret addr
		push rdx
		push rax

		cmp [rdx + 0x28], dword 0
		je .noFloat
			fxsave [rdx + 0x30]
		.noFloat:

		mov rdi, rax
		mov rsi, rdx
		call loadThread

		lea rdi, [rsp + 0x70 + 0x18]
		mov rax, [rsp]
		mov [rax], rdi
		call tssSetRSP0

		pop rax

		;release spinlock on new thread
		lea rdi, [rax + 0x14]
		call releaseSpinlock

		pop rdx
		jmp .end2
	.noSwitch:
		pop rax ;ret addr
		add rsp, 0x30
		push rax
	.end2:
	;release spinlock on old thread
	lea rdi, [rdx + 0x14]
	call releaseSpinlock
	
	ret

jiffyIrq:
	;save mandatory registers
	sub rsp, 0x48
	mov [rsp + 0x40], rax
	mov [rsp + 0x38], rcx
	mov [rsp + 0x30], rdx
	mov [rsp + 0x28], rsi
	mov [rsp + 0x20], rdi
	mov [rsp + 0x18], r8
	mov [rsp + 0x10], r9
	mov [rsp + 0x08], r10
	mov [rsp], r11

	mov rax, 0xffffffff80000000
	cmp [rsp + 0x48], rax
	jae .noswapgs
		;interrupted from userspace
		swapgs
		or [rsp + 0x68], dword 3 ;virtualbox clears dpl for some reason
	.noswapgs:

	mov rdi, [gs:8]
	call sleepSkipTime
	mov esi, eax
	
	mov rax, [gs:8]
	test rax, rax
	jz .return
	cmp [rax + 0x10], dword 1
	jne .return

	mov edx, 1
	call reschedCommon

	.return:
	call ackIRQ

	cmp [perCpuTimer], dword 0
	jne .noIPI
		mov edi, 0xC3
		xor esi, esi
		call lapicSendIPIToAll ;send resched IPI
	.noIPI:

	inc qword [jiffyCounter]

	mov rax, 0xffffffff80000000
	cmp [rsp + 0x48], rax
	jae .noswapgs2
		swapgs
	.noswapgs2:

	;Restore mandatory registers
	mov rax, [rsp + 0x40]
	mov rcx, [rsp + 0x38]
	mov rdx, [rsp + 0x30]
	mov rsi, [rsp + 0x28]
	mov rdi, [rsp + 0x20]
	mov r8,  [rsp + 0x18]
	mov r9,  [rsp + 0x10]
	mov r10, [rsp + 0x08]
	mov r11, [rsp]
	add rsp, 0x48
	iretq

reschedIPI:
	;save mandatory registers
	sub rsp, 0x48
	mov [rsp + 0x40], rax
	mov [rsp + 0x38], rcx
	mov [rsp + 0x30], rdx
	mov [rsp + 0x28], rsi
	mov [rsp + 0x20], rdi
	mov [rsp + 0x18], r8
	mov [rsp + 0x10], r9
	mov [rsp + 0x08], r10
	mov [rsp], r11

	mov rax, 0xffffffff80000000
	cmp [rsp + 0x48], rax
	jae .noswapgs
		swapgs
		or [rsp + 0x68], dword 3
	.noswapgs:

	mov rax, [gs:8]
	test rax, rax
	jz .return
	cmp [rax + 0x10], dword 1
	jne .return

	xor edx, edx
	;mov esi, 1
	xor esi, esi
	call reschedCommon

	.return:
	call ackIRQ

	mov rax, 0xffffffff80000000
	cmp [rsp + 0x48], rax
	jae .noswapgs2
		swapgs
	.noswapgs2:

	;Restore mandatory registers
	mov rax, [rsp + 0x40]
	mov rcx, [rsp + 0x38]
	mov rdx, [rsp + 0x30]
	mov rsi, [rsp + 0x28]
	mov rdi, [rsp + 0x20]
	mov r8,  [rsp + 0x18]
	mov r9,  [rsp + 0x10]
	mov r10, [rsp + 0x08]
	mov r11, [rsp]
	add rsp, 0x48
	iretq

migrateMainStack:
	;rdi contains thread pointer
	mov r8, rdi

	std
	mov rsi, initStackEnd
	xor eax, eax
	;lea rcx, [initStackEnd - rsp]
	mov rcx, initStackEnd
	sub rcx, rsp
	add rcx, 8
	rep movsb
	cld

	;mov r8, rdi
	sub r8, initStackEnd
	add rsp, r8
	;add rbp, r8
	ret

kthreadStop:
	;load return address in rdx
	pop rdx
	;setup stack for iret
	;push ss
	push 0x10
	;push stackpointer
	lea rax, [rsp + 8]
	push rax
	;push flags
	pushfq
	;push cs
	push 0x08
	;push return address
	push rdx

	
	;save opt regs only
	sub rsp, 0x78
	mov [rsp + 0x28], rbx
	mov [rsp + 0x20], rbp
	mov [rsp + 0x18], r12
	mov [rsp + 0x10], r13
	mov [rsp + 0x08], r14
	mov [rsp], r15

	call getCurrentThread

	test [rax + 0x14], dword 0x02 ;get IF on spinlock
	jz .noIRQ
		or [rsp + 0x88], dword (1 << 9) ;set IF on stack
	.noIRQ:

	mov [rax], rsp ;save rsp
	mov r15, rax

	cmp [r15 + 0x28], dword 0
	je .noFloat
		fxsave [r15 + 0x30]
	.noFloat:

	;switch to exception stack
	mov rsp, [gs:0x10]
	;mov rbp, [gs:0x10]

	xor edi, edi
	call setCurrentThread

	and [r15 + 0x14], dword ~2
	lea rdi, [r15 + 0x14]
	call releaseSpinlock

	xor r13d, r13d

nextThread: ;r15 = old thread, r13 = clean up
	call readyQueuePop
	mov r14, rax ;r14 = new thread

	;Halt if no task is available
	test rax, rax
	jnz .load
		test r15, r15
		jz .load2
		mov rcx, [r15 + 0x20]
		test rcx, rcx
		jz .load2
			mov rdx, [initProcess + 0x8]
			mov cr3, rdx ;Do cr3 switch if old thread was userspace
		.load2:
		sti
		hlt
		cli
		jmp nextThread
	.load:

	test r13, r13
	jnz .c
		xor r15d, r15d
		jmp .diffThread
	.c:
	cmp r14, r15
	je .sameThread
		.diffThread:
		;should always happen
		lea rdi, [r14 + 0x14]
		call acquireSpinlock
	.sameThread:

	mov rdi, r14
	mov rsi, [r14]
	mov r13, rsi
	call handleSignal

	mov [r14 + 0x10], dword 1 ;set threadstate to RUNNING

	cmp r14, r15
	je .sameThread2
		mov rsp, r13 ;switch to new stack

		mov rdi, r14
		call loadThread

		lea rdi, [rsp + 0xA0]
		mov [r14], rdi
		call tssSetRSP0

		mov rdi, r14
		call setCurrentThread

		lea rdi, [r14 + 0x14]
		call releaseSpinlock
	.sameThread2:

	test r15, r15
	jz .notDetached

	mov r13d, [r15 + 0x18] ;get old thread detached
	lea rdi, [r15 + 0x14]
	call releaseSpinlock ;release spinlock on old thread

	test r13d, r13d ;is the old thread detached?
	jz .notDetached
		;is the old thread finished?
		mov eax, [r15 + 0x10]
		test eax, eax
		jnz .notDetached
			;dealloc old thread
			mov rdi, r15
			call deallocThread
	.notDetached:

	mov rax, 0xffffffff80000000
	cmp [rsp + 0x78], rax
	jae .noswapgs
		swapgs
	.noswapgs:

	;Restore registers
	mov rax, [rsp + 0x70]
	mov rcx, [rsp + 0x68]
	mov rdx, [rsp + 0x60]
	mov rsi, [rsp + 0x58]
	mov rdi, [rsp + 0x50]
	mov r8,  [rsp + 0x48]
	mov r9,  [rsp + 0x40]
	mov r10, [rsp + 0x38]
	mov r11, [rsp + 0x30]
	mov rbx, [rsp + 0x28]
	mov rbp, [rsp + 0x20]
	mov r12, [rsp + 0x18]
	mov r13, [rsp + 0x10]
	mov r14, [rsp + 0x08]
	mov r15, [rsp]
	add rsp, 0x78
	iretq

SECTION .bss

jiffyCounter: resq 1